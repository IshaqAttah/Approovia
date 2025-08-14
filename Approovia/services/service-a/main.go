package main

import (
        "log"
        "net/http"
)

func main() {
        // Health check endpoint
        http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
                w.WriteHeader(http.StatusOK)
                w.Write([]byte("OK"))
        })

        // Main endpoint
        http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
                w.Write([]byte("Hello from A"))
        })

        port := "8080"
        log.Printf("Service A starting on port %s", port)

        if err := http.ListenAndServe(":"+port, nil); err != nil {
                log.Fatal("Server failed to start:", err)
        }
}
