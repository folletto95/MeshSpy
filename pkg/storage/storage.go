package storage

import (
	"log"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type NodeData struct {
	ID          uint `gorm:"primaryKey"`
	NodeID      string
	Timestamp   time.Time
	Temperature float32
	Humidity    float32
}

type DB struct {
	conn *gorm.DB
}

func NewDatabase(path string) *DB {
	db, err := gorm.Open(sqlite.Open(path), &gorm.Config{})
	if err != nil {
		log.Fatalf("failed to connect database: %v", err)
	}

	err = db.AutoMigrate(&NodeData{})
	if err != nil {
		log.Fatalf("migration failed: %v", err)
	}

	return &DB{conn: db}
}

func (d *DB) SaveNodeData(data *NodeData) error {
	return d.conn.Create(data).Error
}
