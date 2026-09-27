<?php
class T {
    public function run($cmd) {
        $token = md5(uniqid());
        shell_exec($cmd);
    }
}
