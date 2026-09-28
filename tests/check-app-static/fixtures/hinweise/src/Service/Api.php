<?php
namespace App\Service;
class Api {
    public function fetch() {
        $client = new \GuzzleHttp\Client(['base_uri' => 'https://example.test']);
        $body = file_get_contents('https://example.test/x');
        return ['body' => $body];
    }
}
