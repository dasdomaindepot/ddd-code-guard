<?php

namespace App\Form;

use App\Security\PasswordRules;
use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\Form\Extension\Core\Type\PasswordType;
use Symfony\Component\Validator\Constraints as Length;
use Symfony\Component\Security\Core\Validator\Constraints\UserPassword;

class ChangePasswordType extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder->add('currentPassword', PasswordType::class, [
            'constraints' => [new UserPassword()],
        ]);
        $builder->add('plainPassword', PasswordType::class, [
            'constraints' => [
                PasswordRules::constraints(),
                new Length(min: PasswordRules::MIN),
            ],
        ]);
    }
}
