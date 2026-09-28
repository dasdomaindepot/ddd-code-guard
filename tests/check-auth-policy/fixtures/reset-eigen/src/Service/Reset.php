<?php

declare(strict_types=1);

namespace App\Service;

// Regression: Reset-Token aus vorhersagbaren Zutaten erzeugt.
final class Reset
{
    public function resetUser(object $user): void
    {
        $user->setResetToken(md5(uniqid()));
    }
}
