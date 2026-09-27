<?php

declare(strict_types=1);

namespace App\Form;

use App\Validator\PasswortRegeln;
use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\Extension\Core\Type\PasswordType;
use Symfony\Component\Form\Extension\Core\Type\TextType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\Validator\Constraints\Length;

// Regression: Die Length am Benutzernamen steht nahe am Passwortfeld,
// ist aber keine Passwortregel.
final class RegistrationFormType extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder
            ->add('username', TextType::class, [
                'constraints' => [new Length(min: 3, max: 30)],
            ])
            ->add('plainPassword', PasswordType::class, [
                'constraints' => [new Length(min: PasswortRegeln::MINDESTLAENGE)],
            ]);
    }
}
