package api

import (
	"fmt"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

const (
	DirectionAsc  string = "asc"
	DirectionDesc string = "desc"
)

func ErrorMsgf(c *gin.Context, code int, err error, format string, a ...interface{}) {
	var msg string
	if len(a) != 0 {
		msg = fmt.Sprintf(format, a...)
	} else {
		msg = fmt.Sprintf(format)
	}

	if err != nil {
		logrus.WithError(err).Errorf(msg)
	} else {
		logrus.Errorf(msg)
	}

	c.JSON(code, gin.H{
		"msg":  msg,
		"code": code,
	})
}
