package mqttclient

import (
	"log"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"google.golang.org/protobuf/proto"

	"meshspy/internal/proto/local" // importa correttamente il package
)

type MQTTClient struct {
	client mqtt.Client
}

func NewMQTTClient(broker, clientID string) *MQTTClient {
	opts := mqtt.NewClientOptions().
		AddBroker(broker).
		SetClientID(clientID).
		SetKeepAlive(2 * time.Second).
		SetPingTimeout(1 * time.Second)

	client := mqtt.NewClient(opts)
	if token := client.Connect(); token.Wait() && token.Error() != nil {
		log.Fatalf("MQTT connect error: %v", token.Error())
	}

	return &MQTTClient{client: client}
}

func (m *MQTTClient) Publish(topic string, data *meshspy.NodeData) error {
	payload, err := proto.Marshal(data)
	if err != nil {
		return err
	}

	token := m.client.Publish(topic, 0, false, payload)
	token.Wait()
	return token.Error()
}

func (m *MQTTClient) Subscribe(topic string, handler func(*meshspy.NodeData)) {
	m.client.Subscribe(topic, 0, func(client mqtt.Client, msg mqtt.Message) {
		var data meshspy.NodeData
		err := proto.Unmarshal(msg.Payload(), &data)
		if err != nil {
			log.Printf("Invalid protobuf: %v", err)
			return
		}
		handler(&data)
	})
}