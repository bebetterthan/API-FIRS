<?php
namespace FIRS;


class SearchEngine {
    private $config;
    private $indexFile;

    public function __construct($config) {
        $this->config = $config;
        $this->indexFile = $this->config['paths']['invoice_index'];
    }


    public function search(array $filters): array {
        $index = $this->loadIndex();
        $invoices = $index['invoices'] ?? [];


        $filtered = $this->applyFilters($invoices, $filters);


        $sorted = $this->sortResults($filtered, $filters);


        $paginated = $this->paginate($sorted, $filters);

        return $paginated;
    }


    private function loadIndex(): array {
        if (!file_exists($this->indexFile)) {
            return ['invoices' => [], 'total_count' => 0];
        }

        $content = file_get_contents($this->indexFile);
        return json_decode($content, true) ?? ['invoices' => [], 'total_count' => 0];
    }


    private function applyFilters(array $invoices, array $filters): array {
        $results = $invoices;


        if (isset($filters['irn']) && !empty($filters['irn'])) {
            $searchIRN = $filters['irn'];
            $results = array_filter($results, function($invoice) use ($searchIRN) {

                if (str_ends_with($searchIRN, '*')) {
                    $prefix = rtrim($searchIRN, '*');
                    return str_starts_with($invoice['irn'], $prefix);
                }
                return stripos($invoice['irn'], $searchIRN) !== false;
            });
        }


        if (isset($filters['business_id']) && !empty($filters['business_id'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return $invoice['business_id'] === $filters['business_id'];
            });
        }


        if (isset($filters['date_from'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return $invoice['issue_date'] >= $filters['date_from'];
            });
        }

        if (isset($filters['date_to'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return $invoice['issue_date'] <= $filters['date_to'];
            });
        }


        if (isset($filters['payment_status']) && !empty($filters['payment_status'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return strcasecmp($invoice['payment_status'], $filters['payment_status']) === 0;
            });
        }


        if (isset($filters['supplier']) && !empty($filters['supplier'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return stripos($invoice['summary']['supplier'], $filters['supplier']) !== false;
            });
        }


        if (isset($filters['customer']) && !empty($filters['customer'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return stripos($invoice['summary']['customer'], $filters['customer']) !== false;
            });
        }


        if (isset($filters['min_amount'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return $invoice['summary']['total_amount'] >= floatval($filters['min_amount']);
            });
        }

        if (isset($filters['max_amount'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return $invoice['summary']['total_amount'] <= floatval($filters['max_amount']);
            });
        }


        if (isset($filters['currency']) && !empty($filters['currency'])) {
            $results = array_filter($results, function($invoice) use ($filters) {
                return $invoice['summary']['currency'] === $filters['currency'];
            });
        }


        if (isset($filters['signed'])) {
            $signedFilter = filter_var($filters['signed'], FILTER_VALIDATE_BOOLEAN);
            $results = array_filter($results, function($invoice) use ($signedFilter) {
                return $invoice['signed'] === $signedFilter;
            });
        }

        return array_values($results);
    }


    private function sortResults(array $invoices, array $filters): array {
        $sortBy = $filters['sort_by'] ?? 'issue_date';
        $sortOrder = strtolower($filters['sort_order'] ?? 'desc');

        usort($invoices, function($a, $b) use ($sortBy, $sortOrder) {
            $valueA = $this->getSortValue($a, $sortBy);
            $valueB = $this->getSortValue($b, $sortBy);

            if ($sortOrder === 'asc') {
                return $valueA <=> $valueB;
            } else {
                return $valueB <=> $valueA;
            }
        });

        return $invoices;
    }


    private function getSortValue(array $invoice, string $field) {
        switch ($field) {
            case 'total_amount':
                return $invoice['summary']['total_amount'] ?? 0;
            case 'signed_at':
                return strtotime($invoice['signed_at'] ?? '');
            case 'issue_date':
            default:
                return strtotime($invoice['issue_date'] ?? '');
        }
    }


    private function paginate(array $invoices, array $filters): array {
        $page = max(1, intval($filters['page'] ?? 1));
        $perPage = min(100, max(1, intval($filters['per_page'] ?? 20)));

        $totalResults = count($invoices);
        $totalPages = ceil($totalResults / $perPage);
        $offset = ($page - 1) * $perPage;

        $pageResults = array_slice($invoices, $offset, $perPage);

        return [
            'results' => $pageResults,
            'pagination' => [
                'current_page' => $page,
                'per_page' => $perPage,
                'total_results' => $totalResults,
                'total_pages' => $totalPages,
                'has_next' => $page < $totalPages,
                'has_previous' => $page > 1,
            ],
            'filters_applied' => array_filter($filters, function($value) {
                return !empty($value);
            }),
        ];
    }
}
