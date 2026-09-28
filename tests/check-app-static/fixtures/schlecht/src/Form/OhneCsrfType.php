<?php
namespace App\Form;
class OhneCsrfType
{
    public function configureOptions($resolver): void
    {
        $resolver->setDefaults(['csrf_protection' => false]);
    }
}
