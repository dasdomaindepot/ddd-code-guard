<?php

declare(strict_types=1);

namespace App\Controller;

// Regression: Mindestlänge von Hand geprüft statt per Length-Constraint.
final class PasswordResetApiController
{
    public function reset(?string $newPassword): bool
    {
        if ($newPassword === null || strlen($newPassword) < 8) {
            return false;
        }
        $this->hasher->hashPassword($this->user, $newPassword);

        return true;
    }
}
