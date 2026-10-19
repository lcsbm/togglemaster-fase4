module auth-service

go 1.21

require (
	github.com/jackc/pgx/v5 v5.9.0
	github.com/joho/godotenv v1.5.1
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.68.0
	go.opentelemetry.io/otel v1.43.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.43.0
	go.opentelemetry.io/otel/sdk v1.43.0
	golang.org/x/net v0.60.0
	google.golang.org/grpc v1.83.2
)
