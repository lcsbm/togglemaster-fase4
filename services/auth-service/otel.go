package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// initTracer configura o TracerProvider com exporter OTLP gRPC.
// Retorna uma função de shutdown que deve ser chamada no defer do main.
func initTracer(ctx context.Context) func(context.Context) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector.monitoring.svc.cluster.local:4317"
	}

	conn, err := grpc.NewClient(endpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		log.Printf("OTEL: falha ao conectar ao collector (%s): %v — traces desabilitados", endpoint, err)
		return func(context.Context) {}
	}

	exp, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		log.Printf("OTEL: falha ao criar exporter: %v — traces desabilitados", err)
		return func(context.Context) {}
	}

	svcName := os.Getenv("OTEL_SERVICE_NAME")
	if svcName == "" {
		svcName = "auth-service"
	}

	res := resource.NewWithAttributes(
		semconv.SchemaURL,
		semconv.ServiceName(svcName),
		semconv.DeploymentEnvironment(os.Getenv("OTEL_RESOURCE_ATTRIBUTES")),
	)

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("OTEL: TracerProvider inicializado (endpoint: %s, service: %s)", endpoint, svcName)

	return func(ctx context.Context) {
		if err := tp.Shutdown(ctx); err != nil {
			log.Printf("OTEL: erro no shutdown: %v", err)
		}
	}
}
