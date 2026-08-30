namespace ReceivePaymentServicesFA.Settings;

public class AppSettings
{
    public string JHA_POSTING_BASE_URL { get; set; }
    public string JHA_POSTING_PATH { get; set; }
    public string JHA_SEND_APIKEY { get; set; }
    public string JHA_SEND_CLIENT_ID { get; set; }
    public string JHA_SEND_MERCHANT_ID { get; set; }
    public string JHA_DEP_HISTORY_BASE_URL { get; set; }
    public string JHA_DEP_HISTORY_APIKEY { get; set; }
    public string JHA_DEP_HISTORY_CLIENT_ID { get; set; }
    public string JHA_DEP_HISTORY_MERCHANT_ID { get; set; }
    public int JHA_NIGHTLY_UPDATE_REQUEUE_TIME { get; set; }
    public string PREFUND_LEDGER_BASE_URL { get; set; }
    public string PREFUND_LEDGER_RECEIVE_PATH { get; set; }
    public string PREFUND_LEDGER_STATUS_PATH { get; set; }
    public string TRANSFER_BASE_URL { get; set; }
    public string TRANSFER_RECEIVE_PATH { get; set; }
    public string RTP_SEND_APIKEY { get; set; }
    public string COSMOS_PAYMENT_CONNSTRING { get; set; }
    public string COSMOS_PAYMENT_DATABASE { get; set; }
    public string COSMOS_PAYMENT_CONTAINER { get; set; }
    public string COSMOS_PARTNER_LEDGER_CONTAINER { get; set; }
    public string COSMOS_COUNTER_PARTY_CONTAINER { get; set; }
    public string PARTNER_LEDGER_SPNAME { get; set; }
    public string SERVICE_BUS_CONNSTRING { get; set; }
    public string SERVICE_BUS_TOPIC_NAME { get; set; }
    public string SERVICE_BUS_JHA_SUBSCRIPTION_NAME { get; set; }
    public int PRECHECK_FAILED_RESUBMISSION_MINUTES { get; set; }
    public int PRECHECK_FAILED_PROCESSING_COUNT_LIMIT { get; set; }
    public string PARTNER_LEDGER_SQL_CONNSTRING { get; set; }
    public string RTP_RECEIVE_TRAN_CODE { get; set; }
    public string RTP_RECEIVE_RETURN_TRAN_CODE { get; set; }
    public string SENDGRID_EMAIL_URL { get; set; }
    public string SENDGRID_EMAIL_FROM { get; set; }
    public string SENDGRID_EMAIL_FROM_NAME { get; set; }
    public string SENDGRID_EMAIL_TO { get; set; }
    public string SENDGRID_EMAIL_CC { get; set; }
    public string RTP_DEADLETTER_CRON_TRIGGER { get; set; }
    public string RTP_FLAG_IN_PROGRESS_CRON_TRIGGER { get; set; }
    public int RTP_FLAG_IN_PROGRESS_MINUTES { get; set; }
    public string TCH_RETRY_CRON_TRIGGER { get; set; }
    public string TCH_STATUS_URL { get; set; }
    public string TCH_STATUS_HOSTKEY_HEADER { get; set; }
}