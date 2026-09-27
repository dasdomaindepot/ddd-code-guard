<?php

namespace App\Form;

use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\Form\Extension\Core\Type\FileType;

class UploadType extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder): void
    {
        $builder->add('document', FileType::class);
    }
}
