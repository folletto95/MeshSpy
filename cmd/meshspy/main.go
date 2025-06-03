package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"github.com/joho/godotenv" // ← aggiunto per leggere il file .env

	"meshspy/config"
	"meshspy/serial"
	"meshspy/pkg/storage"
	"meshspy/pkg/mqttclient"
	"meshspy/internal/proto/local" // Assicurati sia corretto l'import del pacchetto generato da .proto
	"meshspy/pkg/meshtastic_info" // ✅ nuovo import al posto di client
)

func main() {
	log.Println("🔥 MeshSpy avviamento iniziato...")

	// Carica .env.runtime se presente
	if err := godotenv.Load(".env.runtime"); err != nil {
		log.Printf("⚠️  Nessun file .env.runtime trovato o errore di caricamento: %v", err)
	}

	log.Println("🚀 MeshSpy avviato con successo! Inizializzazione in corso...")

	// DB
	db := storage.NewDatabase("data.db")

	// Carica la configurazione dalle variabili d'ambiente
	cfg := config.Load()

	// MQTT con supporto Protobuf
	client := mqttclient.NewMQTTClient(cfg.MQTTBroker, cfg.ClientID)
	defer client.Disconnect(250)

	// Subscribe per ricevere dati in protobuf dal topic
	client.Subscribe("meshspy/nodes", func(data *meshspy.NodeData) {
		err := db.SaveNodeData(&storage.NodeData{
			NodeID:      data.NodeId,
			Timestamp:   time.Unix(data.Timestamp, 0),
			Temperature: data.Temperature,
			Humidity:    data.Humidity,
		})
		if err != nil {
			log.Printf("DB insert error: %v", err)
		}
	})

	// Inizializza il canale di uscita per la gestione dei segnali di terminazione
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)

	// 📡 Stampa info da meshtastic-go (se disponibile)
	cmd := exec.Command("/usr/local/bin/meshtastic-go", "--port", cfg.SerialPort, "info")
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("⚠️ Errore ottenimento info meshtastic-go: %v", err)
	} else {
		fmt.Printf("ℹ️  Info dispositivo Meshtastic:\n%s\n", output)
	}

	// 💡 Alternativa futura: usa l'oggetto strutturato
	// info, err := meshtastic_info.GetLocalNodeInfo(cfg.SerialPort)
	// if err == nil {
	//     log.Printf("📡 Nodo %s rilevato con firmware %s", info.ID, info.FirmwareVersion)
	// }

	// Avvia la lettura dalla porta seriale in un goroutine
	go func() {
		serial.ReadLoop(cfg.SerialPort, cfg.BaudRate, cfg.Debug, func(data string) {
			// Pubblica ogni messaggio ricevuto sul topic MQTT
			token := client.Publish(cfg.MQTTTopic, 0, false, data)
			token.Wait()
			if token.Error() != nil {
				log.Printf("❌ Errore pubblicazione MQTT: %v", token.Error())
			} else {
				log.Printf("📡 Dato pubblicato su '%s': %s", cfg.MQTTTopic, data)
			}
		})
	}()

	// Mantieni il programma in esecuzione finché non ricevi un segnale di uscita
	<-sigs
	log.Println("👋 Uscita in corso...")
	time.Sleep(time.Second)
}
