// Copyright 2019 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
package events

import (
	"fmt"
	"strings"
	"time"

	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/configuration"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/events"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/leadership"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/sinks/wavefront"
	"github.com/wavefronthq/wavefront-sdk-go/event"

	gometrics "github.com/rcrowley/go-metrics"
	log "github.com/sirupsen/logrus"

	// Pull in both v1 and v2 for v2 events?
	"k8s.io/api/core/v1"

	utilruntime "k8s.io/apimachinery/pkg/util/runtime"

	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	corelisters "k8s.io/client-go/listers/core/v1"
	"k8s.io/client-go/tools/cache"
)

var Log = log.WithField("system", "events")
var leadershipName = "eventRouter"
var filteredEvents = gometrics.GetOrRegisterCounter("events.filtered", gometrics.DefaultRegistry)
var receivedEvents = gometrics.GetOrRegisterCounter("events.received", gometrics.DefaultRegistry)
var sentEvents = gometrics.GetOrRegisterCounter("events.sent", gometrics.DefaultRegistry)

type EventRouter struct {
	kubeClient        kubernetes.Interface
	eLister           corelisters.EventLister
	eListerSynced     cache.InformerSynced
	sink              wavefront.WavefrontSink
	sharedInformers   informers.SharedInformerFactory
	stop              chan struct{}
	daemon            bool
	leadershipManager *leadership.Manager
	filters           eventFilter
}

func NewEventRouter(clientset kubernetes.Interface, cfg configuration.EventsConfig, sink wavefront.WavefrontSink, daemon bool) *EventRouter {
	sharedInformers := informers.NewSharedInformerFactory(clientset, time.Minute)
	eventsInformer := sharedInformers.Core().V1().Events()

	er := &EventRouter{
		kubeClient:      clientset,
		sink:            sink,
		daemon:          daemon,
		sharedInformers: sharedInformers,
		filters:         newEventFilter(cfg.Filters),
	}

	eventsInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: er.addEvent,
	})
	er.eLister = eventsInformer.Lister()
	er.eListerSynced = eventsInformer.Informer().HasSynced

	if er.daemon {
		er.leadershipManager = leadership.NewManager(er, leadershipName, clientset)
	}
	return er
}

func (er *EventRouter) Start() {
	if er.daemon {
		er.leadershipManager.Start()
	} else {
		go func() { er.Resume() }()
	}
}

func (er *EventRouter) Resume() {
	er.stop = make(chan struct{})
	defer utilruntime.HandleCrash()

	Log.Infof("Starting EventRouter")

	go func() { er.sharedInformers.Start(er.stop) }()

	// here is where we kick the caches into gear
	if !cache.WaitForCacheSync(er.stop, er.eListerSynced) {
		utilruntime.HandleError(fmt.Errorf("timed out waiting for caches to sync"))
		return
	}
	<-er.stop

	Log.Infof("Shutting down EventRouter")
}

func (er *EventRouter) Pause() {
	if er.stop != nil {
		close(er.stop)
	}
}

func (er *EventRouter) Stop() {
	if er.daemon {
		er.leadershipManager.Stop()
	}
	er.Pause()
}

// addEvent is called when an event is created, or during the initial list
func (er *EventRouter) addEvent(obj interface{}) {
	e, ok := obj.(*v1.Event)
	if !ok {
		return // prevent unlikely panic
	}

	// ignore events older than a minute to prevent surge on startup
	if e.LastTimestamp.Time.Before(time.Now().Add(-1 * time.Minute)) {
		Log.WithField("event", e.Message).Trace("Ignoring older event")
		return
	}

	ns := e.InvolvedObject.Namespace
	if len(ns) == 0 {
		ns = "default"
	}

	tags := map[string]string{
		"namespace_name": ns,
		"kind":           e.InvolvedObject.Kind,
		"reason":         e.Reason,
		"component":      e.Source.Component,
	}

	resourceName := e.InvolvedObject.Name
	if resourceName != "" {
		if strings.ToLower(e.InvolvedObject.Kind) == "pod" {
			tags["pod_name"] = resourceName
		} else {
			tags["resource_name"] = resourceName
		}
	}

	receivedEvents.Inc(1)
	if !er.filters.matches(tags) {
		if log.IsLevelEnabled(log.TraceLevel) {
			Log.WithField("event", e.Message).Trace("Dropping event")
		}
		filteredEvents.Inc(1)
		return
	}
	sentEvents.Inc(1)

	eType := e.Type
	if len(eType) == 0 {
		eType = "Normal"
	}

	er.sink.ExportEvent(newEvent(
		e.Message,
		e.LastTimestamp.Time,
		e.Source.Host,
		tags,
		event.Type(eType),
	))
}

func newEvent(message string, ts time.Time, host string, tags map[string]string, options ...event.Option) *events.Event {
	// convert tags to annotations
	for k, v := range tags {
		options = append(options, event.Annotate(k, v))
	}

	return &events.Event{
		Message: message,
		Ts:      ts,
		Host:    host,
		Options: options,
	}
}
