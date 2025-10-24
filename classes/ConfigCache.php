<?php
namespace FIRS;

class ConfigCache {
    private static $config = null;
    private static $cacheKey = 'firs_app_config';
    private static $cacheTTL = 3600;

    public static function get(): array {
        if (self::$config !== null) {
            return self::$config;
        }

        if (extension_loaded('apcu') && apcu_enabled()) {
            $cached = apcu_fetch(self::$cacheKey);
            if ($cached !== false) {
                self::$config = $cached;
                return self::$config;
            }
        }

        self::$config = require __DIR__ . '/../config.php';

        if (extension_loaded('apcu') && apcu_enabled()) {
            apcu_store(self::$cacheKey, self::$config, self::$cacheTTL);
        }

        return self::$config;
    }

    public static function clear(): void {
        self::$config = null;
        if (extension_loaded('apcu') && apcu_enabled()) {
            apcu_delete(self::$cacheKey);
        }
    }
}
