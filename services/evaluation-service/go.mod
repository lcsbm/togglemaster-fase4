module evaluation-service

go 1.21

require (
	github.com/aws/aws-sdk-go v1.51.10
	github.com/go-redis/redis/v8 v8.11.5
	github.com/joho/godotenv v1.5.1
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.68.0
	go.opentelemetry.io/otel v1.43.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.43.0
	go.opentelemetry.io/otel/sdk v1.43.0
	go.opentelemetry.io/otel/trace v1.43.0
	golang.org/x/net v0.60.0
	google.golang.org/grpc v1.83.2
)
