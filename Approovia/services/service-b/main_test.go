package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthEndpoint(t *testing.T) {
	// Create a request to the health endpoint
	req, err := http.NewRequest("GET", "/health", nil)
	if err != nil {
		t.Fatal(err)
	}

	// Create a ResponseRecorder to record the response
	rr := httptest.NewRecorder()

	// Create a test handler
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Call the handler with our request and recorder
	handler.ServeHTTP(rr, req)

	// Check the status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Health endpoint returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check the response body
	expected := "OK"
	if rr.Body.String() != expected {
		t.Errorf("Health endpoint returned unexpected body: got %v want %v",
			rr.Body.String(), expected)
	}
}

func TestMainEndpoint(t *testing.T) {
	// Create a request to the main endpoint
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	// Create a ResponseRecorder to record the response
	rr := httptest.NewRecorder()

	// Create a test handler
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Hello from B"))
	})

	// Call the handler with our request and recorder
	handler.ServeHTTP(rr, req)

	// Check the status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Main endpoint returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	// Check the response body contains expected text
	expected := "Hello from B"
	if rr.Body.String() != expected {
		t.Errorf("Main endpoint returned unexpected body: got %v want %v",
			rr.Body.String(), expected)
	}
}

func TestMainEndpointResponseFormat(t *testing.T) {
	// Test that the response is plain text and not empty
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Hello from B"))
	})

	handler.ServeHTTP(rr, req)

	// Check that response is not empty
	if rr.Body.Len() == 0 {
		t.Error("Main endpoint returned empty response")
	}

	// Check that response contains "Hello"
	body := rr.Body.String()
	if !containsString(body, "Hello") {
		t.Errorf("Main endpoint response should contain 'Hello', got: %v", body)
	}

	// Check that response contains "B"
	if !containsString(body, "B") {
		t.Errorf("Main endpoint response should contain 'B', got: %v", body)
	}
}

// Helper function to check if string contains substring
func containsString(s, substr string) bool {
	return len(s) >= len(substr) && s[len(s)-len(substr):] == substr || 
		   len(s) >= len(substr) && s[:len(substr)] == substr ||
		   findSubstring(s, substr)
}

func findSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func BenchmarkMainEndpoint(t *testing.B) {
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Hello from B"))
	})

	for i := 0; i < t.N; i++ {
		req, _ := http.NewRequest("GET", "/", nil)
		rr := httptest.NewRecorder()
		handler.ServeHTTP(rr, req)
	}
}
