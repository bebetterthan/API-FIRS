<?php
namespace FIRS;


class HSNCodeProvider {
    private $config;
    private $hsnFile;
    private static $codesCache = null;

    public function __construct($config) {
        $this->config = $config;
        $this->hsnFile = $this->config['paths']['hsn_codes'];
    }


    private function loadCodes(): array {
        if (self::$codesCache !== null) {
            return self::$codesCache;
        }

        if (!file_exists($this->hsnFile)) {
            return [];
        }

        $content = file_get_contents($this->hsnFile);
        self::$codesCache = json_decode($content, true) ?? [];

        return self::$codesCache;
    }


    public function search(array $filters): array {
        $codes = $this->loadCodes();


        $filtered = $this->applyFilters($codes, $filters);


        $paginated = $this->paginate($filtered, $filters);

        return $paginated;
    }


    private function applyFilters(array $codes, array $filters): array {
        $results = $codes;


        if (isset($filters['code']) && !empty($filters['code'])) {
            $searchCode = $filters['code'];
            $results = array_filter($results, function($hsn) use ($searchCode) {
                return str_starts_with($hsn['code'], $searchCode);
            });
        }


        if (isset($filters['category']) && !empty($filters['category'])) {
            $results = array_filter($results, function($hsn) use ($filters) {
                return strcasecmp($hsn['category'], $filters['category']) === 0;
            });
        }


        if (isset($filters['search']) && !empty($filters['search'])) {
            $searchTerm = $filters['search'];
            $results = array_filter($results, function($hsn) use ($searchTerm) {
                return stripos($hsn['code'], $searchTerm) !== false ||
                       stripos($hsn['description'], $searchTerm) !== false;
            });
        }

        return array_values($results);
    }


    private function paginate(array $codes, array $filters): array {
        $page = max(1, intval($filters['page'] ?? 1));
        $perPage = min(200, max(1, intval($filters['per_page'] ?? 50)));

        $totalResults = count($codes);
        $totalPages = ceil($totalResults / $perPage);
        $offset = ($page - 1) * $perPage;

        $pageResults = array_slice($codes, $offset, $perPage);


        $allCodes = $this->loadCodes();
        $categories = array_unique(array_column($allCodes, 'category'));

        return [
            'codes' => $pageResults,
            'pagination' => [
                'current_page' => $page,
                'per_page' => $perPage,
                'total_results' => $totalResults,
                'total_pages' => $totalPages,
            ],
            'categories' => array_values($categories),
            'total_codes' => count($allCodes),
        ];
    }


    public function getAllCodes(): array {
        return $this->loadCodes();
    }


    public function getByCode(string $code): ?array {
        $codes = $this->loadCodes();

        foreach ($codes as $hsn) {
            if ($hsn['code'] === $code) {
                return $hsn;
            }
        }

        return null;
    }
}
