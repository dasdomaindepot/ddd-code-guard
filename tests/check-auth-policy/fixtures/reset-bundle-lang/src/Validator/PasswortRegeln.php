<?php

namespace App\Validator\Constraints;

use App\Security\UserProvider;
use Symfony\Component\Validator\Constraints as Constraint;
use Symfony\Component\Security\Core\User\UserInterface;

/**
 * Validates the password length of the plain password.
 */
class PasswortRegeln extends Constraint
{
    public const int MINDESTLAENGE = 15;

    public function validate(mixed $value, $context): void
    {
        // At least 15 characters, up to 4096; compared against leaked lists.
        $context->validator->buildValidatorForClass($value)
            ->atLeast(new Constraint\Length(['min' => self::MINDESTLAENGE, 'max' => 4096]))
            ->also(new Constraint\NotCompromisedPassword());
    }
}
