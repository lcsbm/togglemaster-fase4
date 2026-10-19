import os
import sys
import threading
import json
import uuid
import time
import logging
import boto3
from botocore.exceptions import NoCredentialsError, ClientError
from flask import Flask, jsonify
from dotenv import load_dotenv

from opentelemetry import trace
from opentelemetry.trace import StatusCode
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.instrumentation.flask import FlaskInstrumentor

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

def _init_otel():
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.monitoring.svc.cluster.local:4317")
    svc_name = os.getenv("OTEL_SERVICE_NAME", "analytics-service")
    try:
        provider = TracerProvider(resource=Resource({SERVICE_NAME: svc_name}))
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True)))
        trace.set_tracer_provider(provider)
        log.info(f"OTEL: TracerProvider inicializado (endpoint: {endpoint}, service: {svc_name})")
    except Exception as e:
        log.warning(f"OTEL: falha ao inicializar — traces desabilitados: {e}")

_init_otel()
_tracer = trace.get_tracer("analytics-service")

# --- Configuração ---
AWS_REGION = os.getenv("AWS_REGION")
SQS_QUEUE_URL = os.getenv("AWS_SQS_URL")
DYNAMODB_TABLE_NAME = os.getenv("AWS_DYNAMODB_TABLE")

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical("Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.")
    sys.exit(1)

# --- Clientes Boto3 ---
# AWS_ENDPOINT_URL permite apontar para LocalStack em dev local
AWS_ENDPOINT_URL = os.getenv("AWS_ENDPOINT_URL")  # None em produção

try:
    session = boto3.Session(region_name=AWS_REGION)
    sqs_client = session.client("sqs", endpoint_url=AWS_ENDPOINT_URL)
    dynamodb_client = session.client("dynamodb", endpoint_url=AWS_ENDPOINT_URL)
    log.info(f"Clientes Boto3 inicializados na região {AWS_REGION}")
except NoCredentialsError:
    log.critical("Credenciais da AWS não encontradas. Verifique seu ambiente.")
    sys.exit(1)
except Exception as e:
    log.critical(f"Erro ao inicializar o Boto3: {e}")
    sys.exit(1)


# --- SQS Worker ---

def process_message(message):
    """ Processa uma única mensagem SQS e a insere no DynamoDB """
    with _tracer.start_as_current_span("sqs.process_message") as span:
        span.set_attribute("messaging.system", "aws_sqs")
        span.set_attribute("messaging.message_id", message['MessageId'])
        try:
            log.info(f"Processando mensagem ID: {message['MessageId']}")
            body = json.loads(message['Body'])

            event_id = str(uuid.uuid4())
            span.set_attribute("flag.name", body.get('flag_name', ''))
            span.set_attribute("event.id", event_id)

            item = {
                'event_id': {'S': event_id},
                'user_id': {'S': body['user_id']},
                'flag_name': {'S': body['flag_name']},
                'result': {'BOOL': body['result']},
                'timestamp': {'S': body['timestamp']}
            }

            dynamodb_client.put_item(
                TableName=DYNAMODB_TABLE_NAME,
                Item=item
            )

            log.info(f"Evento {event_id} (Flag: {body['flag_name']}) salvo no DynamoDB.")

            sqs_client.delete_message(
                QueueUrl=SQS_QUEUE_URL,
                ReceiptHandle=message['ReceiptHandle']
            )

        except json.JSONDecodeError:
            log.error(f"Erro ao decodificar JSON da mensagem ID: {message['MessageId']}")
            span.set_status(StatusCode.ERROR, "JSON decode error")
        except ClientError as e:
            log.error(f"Erro do Boto3 (DynamoDB ou SQS) ao processar {message['MessageId']}: {e}")
            span.set_status(StatusCode.ERROR, str(e))
        except Exception as e:
            log.error(f"Erro inesperado ao processar {message['MessageId']}: {e}")
            span.set_status(StatusCode.ERROR, str(e))

def sqs_worker_loop():
    """ Loop principal do worker que ouve a fila SQS """
    log.info("Iniciando o worker SQS...")
    while True:
        try:
            # Long-polling: espera até 20s por mensagens
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,  # Processa em lotes de até 10
                WaitTimeSeconds=20
            )
            
            messages = response.get('Messages', [])
            if not messages:
                # Nenhuma mensagem, continua o loop
                continue
                
            log.info(f"Recebidas {len(messages)} mensagens.")
            
            for message in messages:
                process_message(message)
                
        except ClientError as e:
            log.error(f"Erro do Boto3 no loop principal do SQS: {e}")
            time.sleep(10) # Pausa antes de tentar novamente
        except Exception as e:
            log.error(f"Erro inesperado no loop principal do SQS: {e}")
            time.sleep(10)

# --- Servidor Flask (Apenas para Health Check) ---

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

@app.route('/health')
def health():
    # Uma verificação de saúde real poderia checar a conexão com o DynamoDB/SQS
    return jsonify({"status": "ok"})

# --- Inicialização ---

def start_worker():
    """ Inicia o worker SQS em uma thread separada """
    worker_thread = threading.Thread(target=sqs_worker_loop, daemon=True)
    worker_thread.start()

# Inicia o worker SQS em uma thread de background
# Isso garante que ele inicie tanto com 'flask run' quanto com 'gunicorn'
start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8005))
    app.run(host='0.0.0.0', port=port, debug=False)
