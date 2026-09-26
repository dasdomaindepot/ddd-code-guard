<?php

namespace App\Security;

class PasswordRules
{
    public const MIN = 12;

    public static function minimum(): int
    {
        return self::MIN;
    }
}
