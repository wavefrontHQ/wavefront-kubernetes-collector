// Copyright 2018-2019 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

package options

import (
	"time"

	"github.com/spf13/pflag"

	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/flags"
)

type CollectorRunOptions struct {
	// supported flags
	Version         bool
	EnableProfiling bool
	Daemon          bool
	ConfigFile      string
	LogLevel        string
	MaxProcs        int
	UseLegacyEvents bool

	// An experimental flag for forcing a garbage collection and releasing memory.
	// See https://utcc.utoronto.ca/~cks/space/blog/programming/GoNoMemoryFreeing for reference.
	// Basically Go holds on to more memory than is necessary resulting in larger heap usage.
	// Enabling this flag causes the collector to call debug.FreeOSMemory after every sink.send() call.
	// Go 1.13 showed a 30% lower memory usage vs Go 1.12. Enabling this flag was observed to result in a further ~30%
	// reduction in memory usage but the impact of forcing a GC run so frequently has not been thoroughly tested.
	ForceGC bool

	// deprecated flags
	MetricResolution      time.Duration
	Sources               flags.Uris
	Sinks                 flags.Uris
	SinkExportDataTimeout time.Duration
	EnableDiscovery       bool
	EnableRuntimeConfigs  bool
	DiscoveryConfigFile   string
	InternalStatsPrefix   string
	ScrapeTimeout         time.Duration
	logLevel              int
}

func NewCollectorRunOptions() *CollectorRunOptions {
	return &CollectorRunOptions{}
}

func (opts *CollectorRunOptions) AddFlags(fs *pflag.FlagSet) {
	// supported flags
	fs.BoolVar(&opts.Version, "version", false, "print version info and exit")
	fs.BoolVar(&opts.EnableProfiling, "profile", false, "enable pprof")
	fs.BoolVar(&opts.Daemon, "daemon", false, "enable daemon mode")
	fs.StringVar(&opts.ConfigFile, "config_file", "", "required configuration file")
	fs.StringVar(&opts.LogLevel, "log_level", "info", "one of info, debug or trace")
	fs.IntVar(&opts.MaxProcs, "max_procs", 0, "max number of CPUs that can be used simultaneously. Less than 1 for default (number of cores)")
	fs.BoolVar(&opts.ForceGC, "force_gc", false, "experimental flag that periodically forces the release of unused memory")
	fs.BoolVar(&opts.UseLegacyEvents, "use_legacy_events", true, "use legacy Events framework (1.0) instead of new 2.0")

	// deprecated flags
	fs.DurationVar(&opts.MetricResolution, "metric_resolution", 60*time.Second, "The resolution at which the collector will collect metrics")
	fs.MarkDeprecated("metric_resolution", "set defaultCollectionInterval in configuration file")
	fs.Var(&opts.Sources, "source", "source(s) to watch")
	fs.MarkDeprecated("source", "set sources in configuration file")
	fs.Var(&opts.Sinks, "sink", "external sink(s) that receive data")
	fs.MarkDeprecated("sink", "set sinks in configuration file")
	fs.DurationVar(&opts.SinkExportDataTimeout, "sink_export_data_timeout", 20*time.Second, "Timeout for exporting data to a sink")
	fs.MarkDeprecated("sink_export_data_timeout", "set sinkExportDataTimeout in configuration file")
	fs.BoolVar(&opts.EnableDiscovery, "enable-discovery", true, "enable auto discovery")
	fs.MarkDeprecated("enable-discovery", "set enableDiscovery in configuration file")
	fs.BoolVar(&opts.EnableRuntimeConfigs, "enable-runtime-configs", false, "enable runtime configs")
	fs.MarkDeprecated("enable-runtime-configs", "set enable-runtime-configs in configuration file")
	fs.StringVar(&opts.DiscoveryConfigFile, "discovery_config", "", "optional discovery configuration file")
	fs.MarkDeprecated("discovery_config", "set discovery_configs in configuration file")
	fs.StringVar(&opts.InternalStatsPrefix, "internal_stats_prefix", "kubernetes.", "optional prefix for internal collector stats")
	fs.MarkDeprecated("internal_stats_prefix", "set internal_stats_source in configuration file")
	fs.DurationVar(&opts.ScrapeTimeout, "scrape_timeout", 20*time.Second, "The per-source scrape timeout")
	fs.MarkDeprecated("scrape_timeout", "set in configuration file")
	fs.IntVar(&opts.logLevel, "v", 2, "log level for V logs")
	fs.MarkDeprecated("v", "use log_level instead")
}
