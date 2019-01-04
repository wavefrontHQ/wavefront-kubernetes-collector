package prometheus

import (
	"fmt"
	"net/url"

	"github.com/wavefronthq/wavefront-kubernetes-collector/internal/discovery"
	"github.com/wavefronthq/wavefront-kubernetes-collector/plugins/sources/prometheus"

	"github.com/golang/glog"
	"github.com/rcrowley/go-metrics"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var (
	rulesCount metrics.Gauge
)

func init() {
	rulesCount = metrics.GetOrRegisterGauge("discovery.prometheus.rules.count", metrics.DefaultRegistry)
}

type discoverer struct {
	manager discovery.Manager
}

func New(manager discovery.Manager) discovery.Discoverer {
	return &discoverer{
		manager: manager,
	}
}

func (d *discoverer) Discover(ip, resType string, obj metav1.ObjectMeta) error {
	return d.discover(ip, resType, obj, discovery.PrometheusConfig{}, true)
}

func (d *discoverer) Delete(resType string, obj metav1.ObjectMeta) {
	glog.V(5).Infof("%s deleted: %s", resType, obj.Name)
	if d.manager.Registered(obj.Name) != "" {
		providerName := fmt.Sprintf("%s: %s", prometheus.ProviderName, obj.Name)
		d.manager.UnregisterProvider(obj.Name, providerName)
	}
}

func (d *discoverer) Process(cfg discovery.Config) error {
	glog.V(2).Info("loading discovery configuration")
	if len(cfg.PromConfigs) == 0 {
		glog.V(2).Info("empty prometheus discovery configs")
		return nil
	}
	for _, promCfg := range cfg.PromConfigs {
		// default to pod
		if promCfg.ResourceType == "" {
			promCfg.ResourceType = discovery.PodType.String()
		}
		glog.V(4).Infof("%s lookup labels=%v", promCfg.ResourceType, promCfg.Labels)
		switch promCfg.ResourceType {
		case discovery.PodType.String():
			d.discoverPods(promCfg)
		case discovery.ServiceType.String():
			d.discoverServices(promCfg)
		default:
			glog.V(2).Infof("unknown type: %s for rule: %s", promCfg.ResourceType, promCfg.Name)
		}
	}
	rulesCount.Update(int64(len(cfg.PromConfigs)))
	return nil
}

func (d *discoverer) discoverPods(promCfg discovery.PrometheusConfig) error {
	pods, err := d.manager.ListPods(promCfg.Namespace, promCfg.Labels)
	if err != nil {
		return err
	}
	glog.V(4).Infof("%d pods found", len(pods))
	for _, pod := range pods {
		d.discover(pod.Status.PodIP, discovery.PodType.String(), pod.ObjectMeta, promCfg, false)
	}
	return nil
}

func (d *discoverer) discoverServices(promCfg discovery.PrometheusConfig) error {
	services, err := d.manager.ListServices(promCfg.Namespace, promCfg.Labels)
	if err != nil {
		return err
	}
	glog.V(4).Infof("%d services found", len(services))
	for _, service := range services {
		d.discover(service.Spec.ClusterIP, discovery.ServiceType.String(), service.ObjectMeta, promCfg, false)
	}
	return nil
}

func (d *discoverer) discover(ip, resType string, obj metav1.ObjectMeta, config discovery.PrometheusConfig, checkAnnotation bool) error {
	glog.V(5).Infof("%s: %s added | updated namespace: %s", resType, obj.Name, obj.Namespace)

	cachedURL := d.manager.Registered(obj.Name)
	scrapeURL := scrapeURL(ip, resType, obj, config, checkAnnotation)
	if scrapeURL != "" && scrapeURL != cachedURL {
		glog.V(4).Infof("scrapeURL: %s", scrapeURL)
		glog.V(4).Infof("cachedURL: %s", cachedURL)
		u, err := url.Parse(scrapeURL)
		if err != nil {
			glog.Error(err)
			return err
		}
		provider, err := prometheus.NewPrometheusProvider(u)
		if err != nil {
			glog.Error(err)
			return err
		}
		d.manager.RegisterProvider(obj.Name, provider, scrapeURL)
	}
	return nil
}
