package client

import (
	"bufio"
	"bytes"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// NodeInfo rappresenta le informazioni estratte dal dispositivo Meshtastic
type NodeInfo struct {
	ID                string
	LongName          string
	ShortName         string
	MacAddr           string
	HwModel           string
	Role              string
	Latitude          float64
	Longitude         float64
	Altitude          int
	LocationTime      int64
	LocationSource    string
	BatteryLevel      int
	Voltage           float64
	ChannelUtil       float64
	AirUtilTx         float64
	FirmwareVersion   string
	DeviceStateVer    int
	CanShutdown       bool
	HasWifi           bool
	HasBluetooth      bool
	HasEthernet       bool
	RadioRole         string
	PositionFlags     int
	RadioHwModel      string
	HasRemoteHardware bool
}

// Espressioni regolari
var (
	nameRe = regexp.MustCompile(`long_name:"([^"]+)"`)
	fwRe   = regexp.MustCompile(`FirmwareVersion\s+([^\s]+)`)
)

// GetLocalNodeInfo esegue meshtastic-go e recupera i dati dal primo nodo dopo "Radio Settings:"
func GetLocalNodeInfo(port string) (*NodeInfo, error) {
	cmd := exec.Command("/usr/local/bin/meshtastic-go", "--port", port, "info")
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("❌ Errore durante l'esecuzione di meshtastic-go: %v\n", err)
		return nil, err
	}

	scanner := bufio.NewScanner(bytes.NewReader(output))
	var inNodeInfo bool
	node := &NodeInfo{}

	for scanner.Scan() {
		line := scanner.Text()

		if strings.HasPrefix(line, "Node Info") {
			if !inNodeInfo {
				inNodeInfo = true
				continue
			} else {
				break // fermiamoci al secondo nodo
			}
		}

		if !inNodeInfo {
			continue
		}

		switch {
		case strings.HasPrefix(line, "User"):
			re := regexp.MustCompile(`id:"([^"]+)"\s+long_name:"([^"]+)"\s+short_name:"([^"]+)"\s+macaddr:"([^"]+)"\s+hw_model:(\S+)\s+role:(\S+)`)
			matches := re.FindStringSubmatch(line)
			if len(matches) >= 7 {
				node.ID = matches[1]
				node.LongName = matches[2]
				node.ShortName = matches[3]
				node.MacAddr = matches[4]
				node.HwModel = matches[5]
				node.Role = matches[6]
			}
		case strings.HasPrefix(line, "Position"):
			re := regexp.MustCompile(`latitude_i:(\d+)\s+longitude_i:(\d+)\s+altitude:(-?\d+)\s+time:(\d+)\s+location_source:(\S+)`)
			matches := re.FindStringSubmatch(line)
			if len(matches) >= 6 {
				lat, _ := strconv.Atoi(matches[1])
				lon, _ := strconv.Atoi(matches[2])
				node.Latitude = float64(lat) / 1e7
				node.Longitude = float64(lon) / 1e7
				node.Altitude, _ = strconv.Atoi(matches[3])
				node.LocationTime, _ = strconv.ParseInt(matches[4], 10, 64)
				node.LocationSource = matches[5]
			}
		case strings.HasPrefix(line, "DeviceMetrics"):
			re := regexp.MustCompile(`battery_level:(\d+)\s+voltage:(\S+)\s+channel_utilization:(\S+)\s+air_util_tx:(\S+)`)
			matches := re.FindStringSubmatch(line)
			if len(matches) >= 5 {
				node.BatteryLevel, _ = strconv.Atoi(matches[1])
				node.Voltage, _ = strconv.ParseFloat(matches[2], 64)
				node.ChannelUtil, _ = strconv.ParseFloat(matches[3], 64)
				node.AirUtilTx, _ = strconv.ParseFloat(matches[4], 64)
			}
		case strings.HasPrefix(line, "FirmwareVersion"):
			node.FirmwareVersion = strings.TrimSpace(strings.TrimPrefix(line, "FirmwareVersion"))
		case strings.HasPrefix(line, "DeviceStateVersion"):
			node.DeviceStateVer, _ = strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(line, "DeviceStateVersion")))
		case strings.HasPrefix(line, "CanShutdown"):
			node.CanShutdown = strings.Contains(line, "true")
		case strings.HasPrefix(line, "HasWifi"):
			node.HasWifi = strings.Contains(line, "true")
		case strings.HasPrefix(line, "HasBluetooth"):
			node.HasBluetooth = strings.Contains(line, "true")
		case strings.HasPrefix(line, "HasEthernet"):
			node.HasEthernet = strings.Contains(line, "true")
		case strings.HasPrefix(line, "Role"):
			node.RadioRole = strings.TrimSpace(strings.TrimPrefix(line, "Role"))
		case strings.HasPrefix(line, "PositionFlags"):
			node.PositionFlags, _ = strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(line, "PositionFlags")))
		case strings.HasPrefix(line, "HwModel"):
			node.RadioHwModel = strings.TrimSpace(strings.TrimPrefix(line, "HwModel"))
		case strings.HasPrefix(line, "HasRemoteHardware"):
			node.HasRemoteHardware = strings.Contains(line, "true")
		}
	}

	return node, nil
}
