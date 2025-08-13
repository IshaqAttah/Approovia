package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
)

func main() {
    hostname, _ := os.Hostname()
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        response := fmt.Sprintf("Hello from Service A running on %s at %s", 
            hostname, time.Now().Format("2006-01-02 15:04:05"))
        fmt.Fprintf(w, response)
        log.Printf("Service A served request from %s", r.RemoteAddr)
    })
    
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, "OK")
    })
    
    log.Println("Service A starting on port 8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
