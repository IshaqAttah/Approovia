package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHealthEndpoint(t *testing.T) {
	req, err := http.NewRequest("GET", "/health", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(healthHandler)

	handler.ServeHTTP(rr, req)

	// Check status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check response body contains expected content
	expected := "Service B is healthy"
	if !strings.Contains(rr.Body.String(), expected) {
		t.Errorf("handler returned unexpected body: got %v want to contain %v",
			rr.Body.String(), expected)
	}
}

func TestRootEndpoint(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(helloHandler)

	handler.ServeHTTP(rr, req)

	// Check status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check response contains service identifier
	body := rr.Body.String()
	if !strings.Contains(body, "Hello from Service B") {
		t.Errorf("handler returned unexpected body: got %v", body)
	}

	// Check if hostname is included
	if !strings.Contains(body, "running on") {
		t.Errorf("handler should include hostname in response: got %v", body)
	}

	// Check if timestamp is included
	if !strings.Contains(body, "at") {
		t.Errorf("handler should include timestamp in response: got %v", body)
	}
}

func TestServerStartup(t *testing.T) {
	// Test that we can create a server instance
	mux := http.NewServeMux()
	mux.HandleFunc("/", helloHandler)
	mux.HandleFunc("/health", healthHandler)

	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	if server.Addr != ":8080" {
		t.Errorf("Server address not set correctly: got %v want %v",
			server.Addr, ":8080")
	}
}

func TestConcurrentRequests(t *testing.T) {
	// Test concurrent requests to ensure thread safety
	const numRequests = 10
	done := make(chan bool, numRequests)

	for i := 0; i < numRequests; i++ {
		go func() {
			req, _ := http.NewRequest("GET", "/", nil)
			rr := httptest.NewRecorder()
			handler := http.HandlerFunc(helloHandler)
			handler.ServeHTTP(rr, req)

			if rr.Code != http.StatusOK {
				t.Errorf("Concurrent request failed with status: %v", rr.Code)
			}
			done <- true
		}()
	}

	// Wait for all requests to complete with timeout
	timeout := time.After(5 * time.Second)
	for i := 0; i < numRequests; i++ {
		select {
		case <-done:
			// Request completed successfully
		case <-timeout:
			t.Fatalf("Timeout waiting for concurrent requests to complete")
		}
	}
}

func TestResponseFormat(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(helloHandler)
	handler.ServeHTTP(rr, req)

	body := rr.Body.String()
	
	// Test response format: should include service name, hostname, and timestamp
	parts := strings.Split(body, " ")
	
	if len(parts) < 8 {
		t.Errorf("Response format incorrect, expected multiple parts but got: %v", body)
	}

	// Should start with "Hello from Service B"
	if !strings.HasPrefix(body, "Hello from Service B") {
		t.Errorf("Response should start with 'Hello from Service B', got: %v", body)
	}
}

// Test service differentiation
func TestServiceIdentity(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(helloHandler)
	handler.ServeHTTP(rr, req)

	body := rr.Body.String()
	
	// Ensure this is specifically Service B
	if !strings.Contains(body, "Service B") {
		t.Errorf("Service should identify as Service B, got: %v", body)
	}

	// Ensure it's not Service A
	if strings.Contains(body, "Service A") {
		t.Errorf("Service B should not identify as Service A, got: %v", body)
	}
}

// Benchmark tests
func BenchmarkHelloHandler(b *testing.B) {
	req, _ := http.NewRequest("GET", "/", nil)
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		rr := httptest.NewRecorder()
		handler := http.HandlerFunc(helloHandler)
		handler.ServeHTTP(rr, req)
	}
}

func BenchmarkHealthHandler(b *testing.B) {
	req, _ := http.NewRequest("GET", "/health", nil)
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		rr := httptest.NewRecorder()
		handler := http.HandlerFunc(healthHandler)
		handler.ServeHTTP(rr, req)
	}
}
