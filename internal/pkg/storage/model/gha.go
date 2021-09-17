package model

import "time"

var (
	DefaultStartDate = time.Date(1900, 1, 1, 0, 0, 0, 0, time.UTC)
	DefaultEndDate   = time.Date(2100, 1, 1, 0, 0, 0, 0, time.UTC)
)

type GhaActor struct {
	ID          uint   `gorm:"primaryKey"`
	Login       string `gorm:"primaryKey;type:varchar(120)"`
	Name        string `gorm:"type:varchar(120)"`
	CountryID   string `gorm:"type:varchar(2)"`
	CountryName string `gorm:"type:text"`
	Sex         string `gorm:"type:varchar(1)"`
	SexProb     string `gorm:"type:double"`
	Age         int    `gorm:"type:age"`
	Tz          string `gorm:"type:varchar(40)"`
	TzOffset    int    `gorm:"type:int"`

	Names  []GhaActorName  `gorm:"foreignKey:actor_id"`
	Emails []GhaActorEmail `gorm:"foreignKey:actor_id"`
}

func (GhaActor) TableName() string {
	return "gha_actors"
}

type GhaActorName struct {
	ActorID int    `gorm:"primaryKey"`
	Name    string `gorm:"primaryKey"`
	Origin  int
}

func (GhaActorName) TableName() string {
	return "gha_actors_names"
}

type GhaActorEmail struct {
	ActorID int    `gorm:"primaryKey"`
	Email   string `gorm:"primaryKey"`
	Origin  int
}

func (GhaActorEmail) TableName() string {
	return "gha_actors_emails"
}
