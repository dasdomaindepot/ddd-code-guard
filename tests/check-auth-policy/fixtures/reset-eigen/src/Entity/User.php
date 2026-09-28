<?php

declare(strict_types=1);

namespace App\Entity;

use Symfony\Component\Validator\Constraints as Assert;

// Regression: Attribut an einer anderen Eigenschaft direkt über dem Passwort.
class User
{
    private ?string $password = null;

    #[Assert\Length(min: 2)]
    private string $displayName = '';

    private ?string $plainPassword = null;

    private ?string $resetToken = null;
}
