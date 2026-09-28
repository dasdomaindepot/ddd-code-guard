<?php
namespace App\Form;
class SucheType
{
    public function configureOptions($resolver): void
    {
        $resolver->setDefaults(['csrf_protection' => false, 'method' => 'GET']);
    }
}
