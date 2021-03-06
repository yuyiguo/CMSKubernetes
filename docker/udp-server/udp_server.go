package main

// udp_server - UDP Server implementation with optional support to send UDP messages
//              to StompAMQ endpoint
//
// Copyright (c) 2020 - Valentin Kuznetsov <vkuznet@gmail.com>
//

import (
	"encoding/json"
	"flag"
	"io/ioutil"
	"log"
	"net"
	"strings"
	"time"

	"github.com/go-stomp/stomp"
)

// Configuration stores server configuration parameters
type Configuration struct {
	Port        int    `json:"port"`        // server port number
	BufSize     int    `json:"bufSize"`     // buffer size
	StompURI    string `json:"stompURI"`    // Stomp AMQ URI
	Endpoint    string `json:"endpoint"`    // Stomp AMQ endpoint
	ContentType string `json:"contentType"` // ContentType of UDP packet
	Verbose     bool   `json:"verbose"`     // verbose output
}

var Config Configuration

// parseConfig parse given config file
func parseConfig(configFile string) error {
	data, err := ioutil.ReadFile(configFile)
	if err != nil {
		log.Println("Unable to read", err)
		return err
	}
	err = json.Unmarshal(data, &Config)
	if err != nil {
		log.Println("Unable to parse", err)
		return err
	}
	// default values
	if Config.Port == 0 {
		Config.Port = 9331
	}
	if Config.ContentType == "" {
		Config.ContentType = "application/json"
	}
	return nil
}

// udp server implementation
func udpServer() {
	conn, err := net.ListenUDP("udp", &net.UDPAddr{
		Port: Config.Port,
		IP:   net.ParseIP("0.0.0.0"),
	})
	if err != nil {
		panic(err)
	}

	defer conn.Close()
	log.Printf("UDP server %s\n", conn.LocalAddr().String())

	var stompConn *stomp.Conn
	if Config.StompURI != "" {
		netConn, err := net.DialTimeout("tcp", Config.StompURI, 10*time.Second)
		if err != nil {
			log.Printf("Unable to dial to %s, error %v", Config.StompURI, err)
		}

		stompConn, err = stomp.Connect(netConn)
		if err != nil {
			log.Printf("Unable to connect to %s, error %v", Config.StompURI, err)
		}

		defer stompConn.Disconnect()
	}

	for {
		message := make([]byte, Config.BufSize)
		rlen, remote, err := conn.ReadFromUDP(message[:])
		if err != nil {
			log.Printf("Unable to read UDP packet, error %v", err)
			continue
		}

		data := message[:rlen]
		if Config.Verbose {
			sdata := strings.TrimSpace(string(data))
			log.Printf("received: %s from %s\n", sdata, remote)
		}
		if Config.Endpoint != "" && stompConn != nil {
			err = stompConn.Send(Config.Endpoint, Config.ContentType, data)
			if err != nil {
				log.Printf("Unable to send to %s, error %v", Config.Endpoint, data, err)
			}
		}
	}
}

func main() {
	var config string
	flag.StringVar(&config, "config", "", "configuration file")
	flag.Parse()
	err := parseConfig(config)
	if err == nil {
		udpServer()
	}
	log.Fatal(err)
}
