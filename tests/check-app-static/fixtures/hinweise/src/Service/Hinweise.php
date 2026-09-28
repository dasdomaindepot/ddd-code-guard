<?php
namespace App\Service;
class Hinweise {
    /** @var int $x */
    public function run($p, $s, $request) {
        $x = @file_get_contents($p);
        $data = json_decode($s, true);
        $id = (int) $request->query->get('id');
        $mail = 'a@b.de';
        return compact('x', 'data', 'id', 'mail');
    }
}
