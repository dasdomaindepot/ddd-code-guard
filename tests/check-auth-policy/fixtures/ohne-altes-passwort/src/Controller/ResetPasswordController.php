<?php

namespace App\Controller;

use App\Form\ChangePasswordFormType;

class ResetPasswordController
{
    public function reset(): void
    {
        $form = ChangePasswordFormType::class;
        $this->hasher->hashPassword($user, $plain);
    }
}
