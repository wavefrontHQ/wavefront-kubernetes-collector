// Copyright 2018-2019 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

package prometheus

import (
	"fmt"
	"math"
	"strings"
	"time"

	dto "github.com/prometheus/client_model/go"

	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/metrics"
	"github.com/wavefronthq/wavefront-collector-for-kubernetes/internal/util"
)

type pointBuilder struct {
	isValidMetric    func(name string, tags map[string]string) bool
	source           string
	prefix           string
	omitBucketSuffix bool
	tags             map[string]string
	interner         util.StringInterner
}

func NewPointBuilder(src *prometheusMetricsSource) *pointBuilder {
	return &pointBuilder{
		source:           src.source,
		prefix:           src.prefix,
		omitBucketSuffix: src.omitBucketSuffix,
		tags:             src.tags,
		isValidMetric:    src.isValidMetric,
		interner:         util.NewStringInterner(),
	}

}

func (pb *pointBuilder) build(metricFamilies map[string]*dto.MetricFamily) ([]*metrics.MetricPoint, error) {
	now := time.Now().Unix()
	var result []*metrics.MetricPoint

	for metricName, mf := range metricFamilies {
		for _, m := range mf.Metric {
			var points []*metrics.MetricPoint
			if mf.GetType() == dto.MetricType_SUMMARY {
				points = pb.buildSummaryPoints(metricName, m, now, pb.buildTags(m))
			} else if mf.GetType() == dto.MetricType_HISTOGRAM {
				points = pb.buildHistogramPoints(metricName, m, now, pb.buildTags(m))
			} else {
				points = pb.buildPoints(metricName, m, now)
			}

			if len(points) > 0 {
				result = append(result, points...)
			}
		}
	}
	return result, nil
}

func (pb *pointBuilder) metricPoint(name string, value float64, ts int64, source string, tags map[string]string) *metrics.MetricPoint {
	point := &metrics.MetricPoint{
		Metric:    pb.prefix + strings.Replace(name, "_", ".", -1),
		Value:     value,
		Timestamp: ts,
		Source:    source,
	}
	point.SetLabelPairs(pb.deduplicate(tags)) //store tags as LabelPairs for memory optimization
	return point
}

func (pb *pointBuilder) filterAppend(slice []*metrics.MetricPoint, point *metrics.MetricPoint) []*metrics.MetricPoint {
	if pb.isValidMetric(point.Metric, point.GetTags()) {
		return append(slice, point)
	}
	return slice
}

// Get name and value from metric
func (pb *pointBuilder) buildPoints(name string, m *dto.Metric, now int64) []*metrics.MetricPoint {
	var result []*metrics.MetricPoint
	if m.Gauge != nil {
		if !math.IsNaN(m.GetGauge().GetValue()) {
			point := pb.metricPoint(name+".gauge", m.GetGauge().GetValue(), now, pb.source, pb.buildTags(m))
			result = pb.filterAppend(result, point)
		}
	} else if m.Counter != nil {
		if !math.IsNaN(m.GetCounter().GetValue()) {
			point := pb.metricPoint(name+".counter", m.GetCounter().GetValue(), now, pb.source, pb.buildTags(m))
			result = pb.filterAppend(result, point)
		}
	} else if m.Untyped != nil {
		if !math.IsNaN(m.GetUntyped().GetValue()) {
			point := pb.metricPoint(name+".value", m.GetUntyped().GetValue(), now, pb.source, pb.buildTags(m))
			result = pb.filterAppend(result, point)
		}
	}
	return result
}

// Get Quantiles from summary metric
func (pb *pointBuilder) buildSummaryPoints(name string, m *dto.Metric, now int64, tags map[string]string) []*metrics.MetricPoint {
	var result []*metrics.MetricPoint
	for _, q := range m.GetSummary().Quantile {
		if !math.IsNaN(q.GetValue()) {
			newTags := copyOf(tags)
			newTags["quantile"] = fmt.Sprintf("%v", q.GetQuantile())
			point := pb.metricPoint(name, q.GetValue(), now, pb.source, newTags)
			result = pb.filterAppend(result, point)
		}
	}
	point := pb.metricPoint(name+".count", float64(m.GetSummary().GetSampleCount()), now, pb.source, tags)
	result = pb.filterAppend(result, point)
	point = pb.metricPoint(name+".sum", m.GetSummary().GetSampleSum(), now, pb.source, tags)
	result = pb.filterAppend(result, point)

	return result
}

// Get Buckets from histogram metric
func (pb *pointBuilder) buildHistogramPoints(name string, m *dto.Metric, now int64, tags map[string]string) []*metrics.MetricPoint {
	var result []*metrics.MetricPoint
	histName := pb.histogramName(name)
	for _, b := range m.GetHistogram().Bucket {
		newTags := copyOf(tags)
		newTags["le"] = fmt.Sprintf("%v", b.GetUpperBound())
		point := pb.metricPoint(histName, float64(b.GetCumulativeCount()), now, pb.source, newTags)
		result = pb.filterAppend(result, point)
	}
	point := pb.metricPoint(name+".count", float64(m.GetHistogram().GetSampleCount()), now, pb.source, tags)
	result = pb.filterAppend(result, point)
	point = pb.metricPoint(name+".sum", m.GetHistogram().GetSampleSum(), now, pb.source, tags)
	result = pb.filterAppend(result, point)
	return result
}

// Get labels from metric
func (pb *pointBuilder) buildTags(m *dto.Metric) map[string]string {
	tags := make(map[string]string, len(pb.tags)+len(m.Label))
	for k, v := range pb.tags {
		if len(v) > 0 {
			tags[k] = v
		}
	}
	if len(m.Label) >= 0 {
		for _, label := range m.Label {
			if len(label.GetName()) > 0 && len(label.GetValue()) > 0 {
				tags[label.GetName()] = label.GetValue()
			}
		}
	}
	return tags
}

func (pb *pointBuilder) histogramName(name string) string {
	if pb.omitBucketSuffix {
		return name
	}
	return name + ".bucket"
}

func (pb *pointBuilder) deduplicate(tags map[string]string) []metrics.LabelPair {
	result := make([]metrics.LabelPair, 0)
	for k, v := range tags {
		result = append(result, metrics.LabelPair{
			Name:  pb.interner.Intern(k),
			Value: pb.interner.Intern(v),
		})
	}
	return result
}

func copyOf(tags map[string]string) map[string]string {
	newTags := make(map[string]string, len(tags)+1)
	for k, v := range tags {
		newTags[k] = v
	}
	return newTags
}
