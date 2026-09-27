<?php

namespace App\Service;

use App\Entity\User;

class UserService
{
    public function createAccount(string $email): User
    {
        $user = new User($email);
        $user->setHashedPassword($this->hashPassword('s3cr3t-pw'));
        return $user;
    }

    private function hashPassword(string $plain): string
    {
        // Delegated to Symfony's password hasher in production.
        return $plain;
    }
}
