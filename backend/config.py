from pydantic_settings import BaseSettings, SettingsConfigDict

# Eski sürümlerde koda gömülü olan, herkesçe bilinen değerler. Bunlardan biri
# admin anahtarı olarak ayarlanmışsa admin uçları kapalı sayılır.
INSECURE_ADMIN_KEYS = {'', 'okeyx-local-admin-change-me', 'change-me', 'admin', 'password'}


class Settings(BaseSettings):
    app_name:str='OkeyX v12.1.0 API'
    env:str='development'
    host:str='0.0.0.0'
    port:int=10000
    cors_origins:str='http://localhost:3000,http://127.0.0.1:3000'
    supabase_url:str=''
    supabase_anon_key:str=''
    # Yalnızca sunucuda durur (Render ortam değişkeni). Mobil uygulamaya ASLA konmaz.
    supabase_service_role_key:str=''
    supabase_jwt_audience:str='authenticated'
    # Varsayılan boş: ADMIN_KEY ayarlanmadıkça admin uçları kapalıdır.
    admin_key:str=''
    # Test faturalama varsayılan KAPALI. Yalnızca yerel testte bilerek açılır.
    allow_test_billing:bool=False
    owner_player_ids:str=''
    runtime_snapshot_path:str='data/active_rooms.bin'
    runtime_secret:str=''
    google_play_service_account_json:str=''
    android_package:str='com.senshilabs.okeyx_mobile'
    # AdMob ödüllü reklam sunucu doğrulaması (SSV). true iken ödül yalnız Google
    # imzalı geri çağrı geldikten sonra verilir.
    admob_ssv_required:bool=False
    # Firebase Cloud Messaging (HTTP v1) için servis hesabı JSON'u; boşsa push kapalı.
    fcm_service_account_json:str=''
    fcm_project_id:str=''
    local_dev_mode:bool=False
    # Yalnızca local_dev_mode açıkken kullanılır; boşsa bootstrap-local kapalıdır.
    local_test_secret:str=''
    # Hız sınırı (istek/dakika). 0 = kapalı.
    rate_limit_general_per_min:int=300
    rate_limit_auth_per_min:int=60
    rate_limit_sensitive_per_min:int=30
    model_config=SettingsConfigDict(env_file='.env',extra='ignore')

    @property
    def origins(self): return [x.strip() for x in self.cors_origins.split(',') if x.strip()]
    @property
    def owner_ids(self): return {x.strip() for x in self.owner_player_ids.split(',') if x.strip()}
    @property
    def effective_runtime_secret(self)->str:
        """Oda anlık görüntüsü imza anahtarı. Boşsa Supabase servis anahtarından türetilir
        (yeniden başlatmalarda sabit kalır); ikisi de yoksa yalnız yerel geliştirme sabiti."""
        import hashlib
        if self.runtime_secret:
            return self.runtime_secret
        if self.supabase_service_role_key:
            return hashlib.sha256(('okeyx-runtime:'+self.supabase_service_role_key).encode()).hexdigest()
        return 'okeyx-dev-only-runtime'

    @property
    def is_production(self)->bool: return self.env.strip().lower()=='production'
    @property
    def admin_enabled(self)->bool:
        key=(self.admin_key or '').strip()
        return key.lower() not in INSECURE_ADMIN_KEYS and len(key)>=16
    @property
    def remote_store_enabled(self)->bool:
        return bool(self.supabase_url.strip() and self.supabase_service_role_key.strip())
settings=Settings()
