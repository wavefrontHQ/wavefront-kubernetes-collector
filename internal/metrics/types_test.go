// Copyright 2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

package metrics

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetEmptyTags(t *testing.T) {
	point := &MetricPoint{
		Metric:    "test",
		Value:     1,
		Timestamp: 0,
		Source:    "test.source",
	}

	assert.Equal(t, map[string]string{}, point.GetTags(), "expect empty tags")
}

func TestGetTagsLabelPairs(t *testing.T) {
	point := &MetricPoint{
		Metric:    "test",
		Value:     1,
		Timestamp: 0,
		Source:    "test.source",
	}

	name := "name"
	value := "value"
	point.SetLabelPairs([]LabelPair{{
		Name:  &name,
		Value: &value,
	}})

	assert.Equal(t, map[string]string{"name": "value"}, point.GetTags(), "expect tags")
}

func TestGetTagsFromMultipleLabelPairs(t *testing.T) {
	point := &MetricPoint{
		Metric:    "test",
		Value:     1,
		Timestamp: 0,
		Source:    "test.source",
	}

	name := "name"
	name2 := "name2"
	value := "value"
	value2 := "value2"
	point.SetLabelPairs([]LabelPair{
		{Name: &name, Value: &value},
		{Name: &name2, Value: &value2}})

	assert.Equal(t, map[string]string{"name": "value", "name2": "value2"}, point.GetTags(), "expect tags")
}

func TestGetTagsFromTags(t *testing.T) {
	point := &MetricPoint{
		Metric:    "test",
		Value:     1,
		Timestamp: 0,
		Source:    "test.source",
		Tags:      map[string]string{"name": "value"},
	}

	assert.Equal(t, map[string]string{"name": "value"}, point.GetTags(), "expect tags")
}

func TestGetTagsFromTagsAndLabelPairs(t *testing.T) {
	point := &MetricPoint{
		Metric:    "test",
		Value:     1,
		Timestamp: 0,
		Source:    "test.source",
		Tags:      map[string]string{"tag": "tag_value"},
	}

	name := "label_pair"
	value := "label_pair_value"
	point.SetLabelPairs([]LabelPair{{
		Name:  &name,
		Value: &value,
	}})

	assert.Equal(t, map[string]string{"tag": "tag_value", "label_pair": "label_pair_value"}, point.GetTags(), "expect tags")
}
