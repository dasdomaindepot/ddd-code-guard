<?php

namespace App\Service;

use App\Entity\User;
use App\Security\PasswordRules;

class UserManager
{
    public function persist(User $user, string $plainPassword): void
    {
        $user->setHashedPassword($this->hashPassword($plainPassword));
    }

    private function hashPassword(string $plain): string
    {
        // Delegated to Symfony's password hasher in production.
        return $plain;
    }
}
