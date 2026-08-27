from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_name: str = 'OkeyX v10.0.0 API'
    env: str = 'development'
    host: str = '0.0.0.0'
    port: int = 18765
    cors_origins: str = 'http://localhost:3000,http://127.0.0.1:3000'
    supabase_url: str = ''
    supabase_anon_key: str = ''
    supabase_jwt_audience: str = 'authenticated'
    admin_key: str = 'okeyx-local-admin-change-me'
    allow_test_billing: bool = True
    owner_player_ids: str = ''
    runtime_snapshot_path: str = 'data/active_rooms.bin'
    runtime_secret: str = 'okeyx-local-runtime-change-me'
    local_dev_mode: bool = False
    local_test_secret: str = 'okeyx-local-playable-v1113'
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')

    @property
    def origins(self):
        return [x.strip() for x in self.cors_origins.split(',') if x.strip()]

    @property
    def owner_ids(self):
        return {x.strip() for x in self.owner_player_ids.split(',') if x.strip()}
settings = Settings()
