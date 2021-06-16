// Based on https://github.com/kubernetes-retired/heapster/blob/master/metrics/sources/kubelet/kubelet.go
// Diff against master for changes to the original code.

// Copyright 2014 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// This file implements a cadvisor datasource, that collects metrics from an instance
// of cadvisor running on a specific host.

// Copyright 2018-2019 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

package kubelet

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"k8s.io/apimachinery/pkg/types"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"time"

	cadvisor "github.com/google/cadvisor/info/v1"
	"github.com/json-iterator/go"
	log "github.com/sirupsen/logrus"
	v1 "k8s.io/api/core/v1"
	stats "k8s.io/kubernetes/pkg/kubelet/apis/stats/v1alpha1"
)

type Host struct {
	IP       net.IP
	Port     int
	Resource string
}

func (h Host) String() string {
	return net.JoinHostPort(h.IP.String(), strconv.Itoa(h.Port))
}

type KubeletClient struct {
	config *KubeletClientConfig
	client *http.Client
}

type ErrNotFound struct {
	endpoint string
}

func (err *ErrNotFound) Error() string {
	return fmt.Sprintf("%q not found", err.endpoint)
}

func IsNotFoundError(err error) bool {
	_, isNotFound := err.(*ErrNotFound)
	return isNotFound
}

func sampleContainerStats(stats []*cadvisor.ContainerStats) []*cadvisor.ContainerStats {
	if len(stats) == 0 {
		return []*cadvisor.ContainerStats{}
	}
	return []*cadvisor.ContainerStats{stats[len(stats)-1]}
}

func (kc *KubeletClient) postRequestAndGetValue(client *http.Client, req *http.Request, value interface{}) error {
	response, err := client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	body, err := ioutil.ReadAll(response.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body - %v", err)
	}
	if response.StatusCode == http.StatusNotFound {
		return &ErrNotFound{req.URL.String()}
	} else if response.StatusCode != http.StatusOK {
		return fmt.Errorf("request failed - %q, response: %q", response.Status, string(body))
	}

	kubeletAddr := "[unknown]"
	if req.URL != nil {
		kubeletAddr = req.URL.Host
	}

	log.WithFields(log.Fields{
		"address":  kubeletAddr,
		"response": string(body),
	}).Trace("Raw response from kubelet")

	err = jsoniter.ConfigFastest.Unmarshal(body, value)
	if err != nil {
		return fmt.Errorf("failed to parse output. Response: %q. Error: %v", string(body), err)
	}
	return nil
}

func (kc *KubeletClient) parseStat(containerInfo *cadvisor.ContainerInfo) *cadvisor.ContainerInfo {
	containerInfo.Stats = sampleContainerStats(containerInfo.Stats)
	if len(containerInfo.Aliases) > 0 {
		containerInfo.Name = containerInfo.Aliases[0]
	}
	return containerInfo
}

// TODO(vmarmol): Use Kubernetes' if we export it as an API.
type statsRequest struct {
	// The name of the container for which to request stats.
	// Default: /
	ContainerName string `json:"containerName,omitempty"`

	// Max number of stats to return.
	// If start and end time are specified this limit is ignored.
	// Default: 60
	NumStats int `json:"num_stats,omitempty"`

	// Start time for which to query information.
	// If omitted, the beginning of time is assumed.
	Start time.Time `json:"start,omitempty"`

	// End time for which to query information.
	// If omitted, current time is assumed.
	End time.Time `json:"end,omitempty"`

	// Whether to also include information from subcontainers.
	// Default: false.
	Subcontainers bool `json:"subcontainers,omitempty"`
}

func (kc *KubeletClient) getScheme() string {
	if kc.config != nil && kc.config.EnableHttps {
		return "https"
	}
	return "http"
}

func (kc *KubeletClient) getUrl(host Host, path string) string {
	u := url.URL{
		Scheme: kc.getScheme(),
		Host:   host.String(),
		Path:   path,
	}
	return u.String()
}

// Get stats for all non-Kubernetes containers.
func (kc *KubeletClient) GetAllRawContainers(host Host, start, end time.Time) ([]cadvisor.ContainerInfo, error) {
	u := kc.getUrl(host, "/stats/container/")
	return kc.getAllContainers(u, start, end)
}

func (kc *KubeletClient) GetSummary(host Host) (*stats.Summary, error) {
	u := kc.getUrl(host, "/stats/summary/")

	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	summary := &stats.Summary{}
	client := kc.client
	if client == nil {
		client = http.DefaultClient
	}
	err = kc.postRequestAndGetValue(client, req, summary)
	return summary, err
}

func (kc *KubeletClient) GetPods(host Host) (*v1.PodList, error) {
	u := kc.getUrl(host, "/pods/")

	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	pods := &v1.PodList{}
	client := kc.client
	if client == nil {
		client = http.DefaultClient
	}
	err = kc.postRequestAndGetValue(client, req, pods)

	return pods, err
}

func (kc *KubeletClient) GetCAdvisorMetrics(host Host, nodeName types.NodeName) (*v1.PodList, error) {
	u := kc.getUrl(host, fmt.Sprintf("/api/v1/nodes/%s/proxy/metrics/cadvisor", nodeName))
	//u := kc.getUrl(host, "/proxy/metrics/cadvisor")

	log.Info("@@@@@ Here's the URL when we try to do cadvisor stuff")
	log.Info(u)

	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	pods := &v1.PodList{}
	client := kc.client
	if client == nil {
		client = http.DefaultClient
	}
	err = kc.postRequestAndGetValue(client, req, pods)

	return pods, err
}

func (kc *KubeletClient) GetPort() int {
	return int(kc.config.Port)
}

func (kc *KubeletClient) getAllContainers(url string, start, end time.Time) ([]cadvisor.ContainerInfo, error) {
	// Request data from all subcontainers.
	request := statsRequest{
		ContainerName: "/",
		NumStats:      1,
		Start:         start,
		End:           end,
		Subcontainers: true,
	}
	body, err := jsoniter.ConfigFastest.Marshal(request)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	var containers map[string]cadvisor.ContainerInfo
	client := kc.client
	if client == nil {
		client = http.DefaultClient
	}
	err = kc.postRequestAndGetValue(client, req, &containers)
	if err != nil {
		return nil, fmt.Errorf("failed to get all container stats from Kubelet URL %q: %v", url, err)
	}
	result := make([]cadvisor.ContainerInfo, 0, len(containers))
	for _, containerInfo := range containers {
		cont := kc.parseStat(&containerInfo)
		if cont != nil {
			result = append(result, *cont)
		}
	}
	return result, nil
}

func NewKubeletClient(kubeletConfig *KubeletClientConfig) (*KubeletClient, error) {
	transport, err := MakeTransport(kubeletConfig)
	if err != nil {
		return nil, err
	}
	c := &http.Client{
		Transport: transport,
		Timeout:   kubeletConfig.HTTPTimeout,
	}
	return &KubeletClient{
		config: kubeletConfig,
		client: c,
	}, nil
}
