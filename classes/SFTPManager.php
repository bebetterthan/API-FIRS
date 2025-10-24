<?php
namespace FIRS;

use League\Flysystem\Filesystem;
use League\Flysystem\PhpseclibV3\SftpConnectionProvider;
use League\Flysystem\PhpseclibV3\SftpAdapter;
use League\Flysystem\UnixVisibility\PortableVisibilityConverter;


class SFTPManager {
    private $config;
    private $filesystem = null;

    public function __construct($config) {
        $this->config = $config;
    }


    public function connect(): void {
        if ($this->filesystem !== null) {
            return;
        }

        if (!$this->config['sftp']['enabled']) {
            throw new \Exception('SFTP is not enabled in configuration');
        }

        try {
            $provider = new SftpConnectionProvider(
                $this->config['sftp']['host'],
                $this->config['sftp']['username'],
                $this->config['sftp']['password'],
                null,
                null,
                $this->config['sftp']['port']
            );

            $adapter = new SftpAdapter(
                $provider,
                $this->config['sftp']['root_path'],
                PortableVisibilityConverter::fromArray([
                    'file' => ['public' => 0644, 'private' => 0600],
                    'dir' => ['public' => 0755, 'private' => 0700],
                ])
            );

            $this->filesystem = new Filesystem($adapter);

        } catch (\Exception $e) {
            throw new \Exception('SFTP connection failed: ' . $e->getMessage());
        }
    }


    public function listFiles(string $directory): array {
        $this->connect();

        try {
            $contents = $this->filesystem->listContents($directory, false);
            $files = [];

            foreach ($contents as $item) {
                if ($item->isFile()) {
                    $files[] = [
                        'path' => $item->path(),
                        'size' => $item->fileSize(),
                        'timestamp' => $item->lastModified(),
                    ];
                }
            }

            return $files;

        } catch (\Exception $e) {
            throw new \Exception('Failed to list SFTP directory: ' . $e->getMessage());
        }
    }


    public function downloadFile(string $remotePath, string $localPath): bool {
        $this->connect();

        try {
            $content = $this->filesystem->read($remotePath);


            $dir = dirname($localPath);
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }

            file_put_contents($localPath, $content);

            return file_exists($localPath) && filesize($localPath) > 0;

        } catch (\Exception $e) {
            throw new \Exception('Failed to download from SFTP: ' . $e->getMessage());
        }
    }


    public function uploadFile(string $localPath, string $remotePath): bool {
        $this->connect();

        if (!file_exists($localPath)) {
            throw new \Exception('Local file not found: ' . $localPath);
        }

        try {
            $content = file_get_contents($localPath);
            $this->filesystem->write($remotePath, $content);

            return true;

        } catch (\Exception $e) {
            throw new \Exception('Failed to upload to SFTP: ' . $e->getMessage());
        }
    }


    public function moveFile(string $source, string $destination): bool {
        $this->connect();

        try {
            $this->filesystem->move($source, $destination);
            return true;

        } catch (\Exception $e) {
            throw new \Exception('Failed to move file on SFTP: ' . $e->getMessage());
        }
    }


    public function fileExists(string $path): bool {
        $this->connect();

        try {
            return $this->filesystem->fileExists($path);
        } catch (\Exception $e) {
            return false;
        }
    }


    public function deleteFile(string $path): bool {
        $this->connect();

        try {
            $this->filesystem->delete($path);
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }


    public function createStatusFile(string $irn, array $status): bool {
        $this->connect();

        $filename = $irn . '.status.json';
        $path = $this->config['sftp']['paths']['completed'] . '/' . $filename;

        $content = json_encode($status, JSON_PRETTY_PRINT);

        try {
            $this->filesystem->write($path, $content);
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }
}
