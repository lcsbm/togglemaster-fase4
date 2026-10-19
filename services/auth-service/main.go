package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// App struct (para injeção de dependência)
type App struct {
	DB         *sql.DB
	MasterKey  string
}

func main() {
	_ = godotenv.Load()

	ctx := context.Background()
	shutdownTracer := initTracer(ctx)
	defer shutdownTracer(ctx)

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001" // Porta padrão
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL deve ser definida")
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY deve ser definida")
	}

	// --- Conexão com o Banco ---
	db, err := connectDB(databaseURL)
	if err != nil {
		log.Fatalf("Não foi possível conectar ao banco de dados: %v", err)
	}
	defer db.Close()

	if err := migrateDB(db); err != nil {
		log.Fatalf("Falha na migração do banco: %v", err)
	}

	app := &App{
		DB:         db,
		MasterKey:  masterKey,
	}

	// --- Rotas da API ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/validate", app.validateKeyHandler)
	mux.Handle("/admin/keys", app.masterKeyAuthMiddleware(http.HandlerFunc(app.createKeyHandler)))

	// Envolve o mux com o middleware OTel para tracing automático de todas as rotas
	handler := otelhttp.NewHandler(mux, "auth-service")

	log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}

func migrateDB(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS api_keys (
			id         SERIAL PRIMARY KEY,
			name       VARCHAR(100) NOT NULL,
			key_hash   VARCHAR(64)  NOT NULL UNIQUE,
			is_active  BOOLEAN DEFAULT true,
			created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
		)`)
	return err
}

// connectDB inicializa e testa a conexão com o PostgreSQL
func connectDB(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	if err = db.Ping(); err != nil {
		return nil, err
	}

	log.Println("Conectado ao PostgreSQL com sucesso!")
	return db, nil
}