// Copyright 2018-2020 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"fmt"
	"net/http"
	_ "net/http/pprof"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	gm "github.com/rcrowley/go-metrics"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/pflag"

	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/agent"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/configuration"
	kube_config "github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/kubernetes"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/leadership"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/metrics"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/options"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/util"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/discovery"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/events"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/manager"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/processors"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/sinks"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/sinks/wavefront"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/sources"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/plugins/sources/summary"

	kubeFlag "k8s.io/apiserver/pkg/util/flag"
	"k8s.io/apiserver/pkg/util/logs"
	kube_client "k8s.io/client-go/kubernetes"
	v1listers "k8s.io/client-go/listers/core/v1"
)

var (
	version     string
	commit      string
	discWatcher util.FileWatcher
)

func main() {
	log.SetFormatter(&log.TextFormatter{})
	log.SetLevel(log.InfoLevel)
	log.SetOutput(os.Stdout)

	opt := options.NewCollectorRunOptions()
	opt.AddFlags(pflag.CommandLine)
	kubeFlag.InitFlags()

	if opt.Version {
		fmt.Println(fmt.Sprintf("version: %s\ncommit: %s", version, commit))
		os.Exit(0)
	}

	logs.InitLogs()
	defer logs.FlushLogs()

	switch opt.LogLevel {
	case "trace":
		log.SetLevel(log.TraceLevel)
	case "debug":
		log.SetLevel(log.DebugLevel)
	case "warn":
		log.SetLevel(log.WarnLevel)
	}

	log.Infof(strings.Join(os.Args, " "))
	log.Infof("wavefront-collector version %v", version)
	enableProfiling(opt.EnableProfiling)
	enableForcedGC(opt.ForceGC)
	// TODO: use events 2.0 code when this is false
	//enableLegacyEvents(opt.UseLegacyEvents)

	preRegister(opt)
	cfg := loadConfigOrDie(opt.ConfigFile)
	cfg = convertOrDie(opt, cfg)
	ag := createAgentOrDie(cfg)
	registerListeners(ag, opt)
	waitForStop()
}

func preRegister(opt *options.CollectorRunOptions) {
	if opt.Daemon {
		nodeName := util.GetNodeName()
		if nodeName == "" {
			log.Fatalf("missing environment variable %s", util.NodeNameEnvVar)
		}
		err := os.Setenv(util.DaemonModeEnvVar, "true")
		if err != nil {
			log.Fatalf("error setting environment variable %s", util.DaemonModeEnvVar)
		}
		log.Infof("%s: %s", util.NodeNameEnvVar, nodeName)
	}
	setMaxProcs(opt)
	registerVersion()
}

func createAgentOrDie(cfg *configuration.Config) *agent.Agent {
	// when invoked from cfg reloads original command flags will be missing
	// always read from the environment variable
	cfg.Daemon = os.Getenv(util.DaemonModeEnvVar) != ""

	// backwards compat: used by prometheus sources to format histogram metric names
	setEnvVar("omitBucketSuffix", strconv.FormatBool(cfg.OmitBucketSuffix))

	clusterName := cfg.ClusterName

	kubeClient := createKubeClientOrDie(*cfg.Sources.SummaryConfig)
	if cfg.Sources.StateConfig != nil {
		cfg.Sources.StateConfig.KubeClient = kubeClient
	}

	// create sources manager
	sourceManager := sources.Manager()
	sourceManager.SetDefaultCollectionInterval(cfg.DefaultCollectionInterval)
	err := sourceManager.BuildProviders(*cfg.Sources)
	if err != nil {
		log.Fatalf("Failed to create source manager: %v", err)
	}

	// create sink managers
	setInternalSinkProperties(cfg)
	sinkManager := createSinkManagerOrDie(cfg.Sinks, cfg.SinkExportDataTimeout)

	// Events
	var eventRouter *events.EventRouter
	if cfg.EnableEvents {
		events.Log.Info("Events collection enabled")
		eventRouter = events.NewEventRouter(kubeClient, cfg.EventsConfig, sinkManager, cfg.Daemon)
	} else {
		events.Log.Info("Events collection disabled")
	}

	// create data processors
	podLister := getPodListerOrDie(kubeClient)
	dataProcessors := createDataProcessorsOrDie(kubeClient, clusterName, podLister, cfg)

	// create discovery manager
	handler := sourceManager.(metrics.ProviderHandler)
	dm := createDiscoveryManagerOrDie(kubeClient, cfg, handler, podLister)

	// create uber manager
	man, err := manager.NewFlushManager(dataProcessors, sinkManager, cfg.FlushInterval, cfg.FlushOnce)
	if err != nil {
		log.Fatalf("Failed to create main manager: %v", err)
	}

	// start leader-election if daemon mode
	if cfg.Daemon {
		_, err := leadership.Subscribe(kubeClient.CoreV1(), "agent")
		if err != nil {
			log.Fatalf("Failed to start leader election: %v", err)
		}
	}

	// create and start agent
	ag := agent.NewAgent(man, dm, eventRouter)
	ag.Start()
	return ag
}

func loadConfigOrDie(file string) *configuration.Config {
	if file == "" {
		return nil
	}
	log.Infof("loading config: %s", file)

	cfg, err := configuration.FromFile(file)
	if err != nil {
		log.Fatalf("error parsing configuration: %v", err)
		return nil
	}
	fillDefaults(cfg)

	if err := validateCfg(cfg); err != nil {
		log.Fatalf("invalid configuration file: %v", err)
		return nil
	}
	return cfg
}

// use defaults if no values specified in config file
func fillDefaults(cfg *configuration.Config) {
	if cfg.FlushInterval == 0 {
		cfg.FlushInterval = 60 * time.Second
	}
	if cfg.DefaultCollectionInterval == 0 {
		cfg.DefaultCollectionInterval = 60 * time.Second
	}
	if cfg.SinkExportDataTimeout == 0 {
		cfg.SinkExportDataTimeout = 20 * time.Second
	}
	if cfg.ClusterName == "" {
		cfg.ClusterName = "k8s-cluster"
	}
	if cfg.DiscoveryConfig.DiscoveryInterval == 0 {
		cfg.DiscoveryConfig.DiscoveryInterval = 5 * time.Minute
	}
}

// converts flags to configuration for backwards compatibility support
func convertOrDie(opt *options.CollectorRunOptions, cfg *configuration.Config) *configuration.Config {
	// omit flags if config file is provided
	if cfg != nil {
		log.Info("using configuration file, omitting flags")
		return cfg
	}
	optsCfg, err := opt.Convert()
	if err != nil {
		log.Fatalf("error converting flags to config: %v", err)
	}
	fillDefaults(optsCfg)
	return optsCfg
}

func setInternalSinkProperties(cfg *configuration.Config) {
	log.Infof("using clusterName: %s", cfg.ClusterName)
	prefix := ""
	if cfg.Sources.StatsConfig != nil {
		prefix = configuration.GetStringValue(cfg.Sources.StatsConfig.Prefix, "kubernetes.")
	}
	version := getVersion()
	for _, sink := range cfg.Sinks {
		sink.ClusterName = cfg.ClusterName
		sink.InternalStatsPrefix = prefix
		sink.Version = version
		sink.EventsEnabled = cfg.EnableEvents
	}
}

func registerListeners(ag *agent.Agent, opt *options.CollectorRunOptions) {
	handler := &reloader{ag: ag}
	if opt.ConfigFile != "" {
		listener := configuration.NewFileListener(handler)
		watcher := util.NewFileWatcher(opt.ConfigFile, listener, 30*time.Second)
		watcher.Watch()
	}
}

func createDiscoveryManagerOrDie(client *kube_client.Clientset, cfg *configuration.Config,
	handler metrics.ProviderHandler, podLister v1listers.PodLister) *discovery.Manager {

	if cfg.EnableDiscovery {
		serviceLister := getServiceListerOrDie(client)
		nodeLister := getNodeListerOrDie(client)

		return discovery.NewDiscoveryManager(discovery.RunConfig{
			KubeClient:      client,
			DiscoveryConfig: cfg.DiscoveryConfig,
			Handler:         handler,
			Daemon:          cfg.Daemon,
			Lister:          discovery.NewResourceLister(podLister, serviceLister, nodeLister),
		})
	}
	return nil
}

func registerVersion() {
	version := getVersion()
	m := gm.GetOrRegisterGaugeFloat64("version", gm.DefaultRegistry)
	m.Update(version)
}

func getVersion() float64 {
	parts := strings.Split(version, ".")
	friendly := fmt.Sprintf("%s.%s%s", parts[0], parts[1], parts[2])
	f, err := strconv.ParseFloat(friendly, 2)
	if err != nil {
		f = 0.0
	}
	return f
}

func createSinkManagerOrDie(cfgs []*configuration.WavefrontSinkConfig, sinkExportDataTimeout time.Duration) wavefront.WavefrontSink {
	sinksFactory := sinks.NewSinkFactory()
	sinkList := sinksFactory.BuildAll(cfgs)

	for _, sink := range sinkList {
		log.Infof("Starting with %s", sink.Name())
	}
	sinkManager, err := sinks.NewSinkManager(sinkList, sinkExportDataTimeout, sinks.DefaultSinkStopTimeout)
	if err != nil {
		log.Fatalf("Failed to create sink manager: %v", err)
	}
	return sinkManager
}

func getPodListerOrDie(kubeClient *kube_client.Clientset) v1listers.PodLister {
	podLister, err := util.GetPodLister(kubeClient)
	if err != nil {
		log.Fatalf("Failed to create podLister: %v", err)
	}
	return podLister
}

func createKubeClientOrDie(cfg configuration.SummarySourceConfig) *kube_client.Clientset {
	kubeConfig, err := kube_config.GetKubeClientConfig(cfg)
	if err != nil {
		log.Fatalf("Failed to get client config: %v", err)
	}
	return kube_client.NewForConfigOrDie(kubeConfig)
}

func createDataProcessorsOrDie(kubeClient *kube_client.Clientset, cluster string, podLister v1listers.PodLister, cfg *configuration.Config) []metrics.DataProcessor {

	labelCopier, err := util.NewLabelCopier(",", []string{}, []string{})
	if err != nil {
		log.Fatalf("Failed to initialize label copier: %v", err)
	}

	dataProcessors := []metrics.DataProcessor{
		// Convert cumulative to rate
		processors.NewRateCalculator(metrics.RateMetricsMapping),
	}

	collectionInterval := calculateCollectionInterval(cfg)
	podBasedEnricher := processors.NewPodBasedEnricher(podLister, labelCopier, collectionInterval)
	dataProcessors = append(dataProcessors, podBasedEnricher)

	namespaceBasedEnricher, err := processors.NewNamespaceBasedEnricher(kubeClient)
	if err != nil {
		log.Fatalf("Failed to create NamespaceBasedEnricher: %v", err)
	}
	dataProcessors = append(dataProcessors, namespaceBasedEnricher)

	// aggregators
	metricsToAggregate := []string{
		metrics.MetricCpuUsageRate.Name,
		metrics.MetricMemoryUsage.Name,
		metrics.MetricCpuRequest.Name,
		metrics.MetricCpuLimit.Name,
		metrics.MetricMemoryRequest.Name,
		metrics.MetricMemoryLimit.Name,
	}

	metricsToAggregateForNode := []string{
		metrics.MetricCpuRequest.Name,
		metrics.MetricCpuLimit.Name,
		metrics.MetricMemoryRequest.Name,
		metrics.MetricMemoryLimit.Name,
		metrics.MetricEphemeralStorageRequest.Name,
		metrics.MetricEphemeralStorageLimit.Name,
	}

	dataProcessors = append(dataProcessors,
		processors.NewPodAggregator(),
		&processors.NamespaceAggregator{
			MetricsToAggregate: metricsToAggregate,
		},
		&processors.NodeAggregator{
			MetricsToAggregate: metricsToAggregateForNode,
		},
		&processors.ClusterAggregator{
			MetricsToAggregate: metricsToAggregate,
		})

	nodeAutoscalingEnricher, err := processors.NewNodeAutoscalingEnricher(kubeClient, labelCopier)
	if err != nil {
		log.Fatalf("Failed to create NodeAutoscalingEnricher: %v", err)
	}
	dataProcessors = append(dataProcessors, nodeAutoscalingEnricher)

	// this always needs to be the last processor
	wavefrontCoverter, err := summary.NewPointConverter(*cfg.Sources.SummaryConfig, cluster)
	if err != nil {
		log.Fatalf("Failed to create WavefrontPointConverter: %v", err)
	}
	dataProcessors = append(dataProcessors, wavefrontCoverter)

	return dataProcessors
}

func calculateCollectionInterval(cfg *configuration.Config) time.Duration {
	collectionInterval := cfg.DefaultCollectionInterval
	if cfg.Sources.SummaryConfig.Collection.Interval > 0 {
		collectionInterval = cfg.Sources.SummaryConfig.Collection.Interval
	}
	return collectionInterval
}

func getServiceListerOrDie(kubeClient *kube_client.Clientset) v1listers.ServiceLister {
	serviceLister, err := util.GetServiceLister(kubeClient)
	if err != nil {
		log.Fatalf("Failed to create serviceLister: %v", err)
	}
	return serviceLister
}

func getNodeListerOrDie(kubeClient *kube_client.Clientset) v1listers.NodeLister {
	nodeLister, _, err := util.GetNodeLister(kubeClient)
	if err != nil {
		log.Fatalf("Failed to create nodeLister: %v", err)
	}
	return nodeLister
}

func validateCfg(cfg *configuration.Config) error {
	if cfg.FlushInterval < 5*time.Second {
		return fmt.Errorf("metric resolution should not be less than 5 seconds: %d", cfg.FlushInterval)
	}
	if cfg.Sources == nil {
		return fmt.Errorf("missing sources")
	}
	if cfg.Sources.SummaryConfig == nil {
		return fmt.Errorf("kubernetes_source is missing")
	}
	if len(cfg.Sinks) == 0 {
		return fmt.Errorf("missing sink")
	}
	return nil
}

func setMaxProcs(opt *options.CollectorRunOptions) {
	// Allow as many threads as we have cores unless the user specified a value.
	var numProcs int
	if opt.MaxProcs < 1 {
		numProcs = runtime.NumCPU()
		if numProcs == 1 {
			// default to 2
			numProcs = 2
		}
	} else {
		numProcs = opt.MaxProcs
	}
	runtime.GOMAXPROCS(numProcs)

	// Check if the setting was successful.
	actualNumProcs := runtime.GOMAXPROCS(0)
	if actualNumProcs != numProcs {
		log.Warningf("Specified max procs of %d but using %d", numProcs, actualNumProcs)
	}
}

func enableProfiling(enable bool) {
	if enable {
		go func() {
			log.Info("Starting pprof server at: http://localhost:9090/debug/pprof")
			if err := http.ListenAndServe("localhost:9090", nil); err != nil {
				log.Errorf("E! %v", err)
			}
		}()
	}
}

func enableForcedGC(enable bool) {
	if enable {
		log.Info("enabling forced garbage collection")
		setEnvVar(util.ForceGC, "true")
	}
}

func setEnvVar(key, val string) {
	err := os.Setenv(key, val)
	if err != nil {
		log.Errorf("error setting environment variable %s: %v", key, err)
	}
}

func waitForStop() {
	select {}
}

type reloader struct {
	mtx sync.Mutex
	ag  *agent.Agent
}

// Handles changes to collector or discovery configuration
func (r *reloader) Handle(cfg interface{}) {
	r.mtx.Lock()
	defer r.mtx.Unlock()

	switch cfg.(type) {
	case *configuration.Config:
		r.handleCollectorCfg(cfg.(*configuration.Config))
	}
}

func (r *reloader) handleCollectorCfg(cfg *configuration.Config) {
	log.Infof("collector configuration changed")

	fillDefaults(cfg)

	// stop the previous agent and start a new agent
	r.ag.Stop()
	r.ag = createAgentOrDie(cfg)
}
