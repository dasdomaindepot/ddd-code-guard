<?php

namespace App\Entity;

use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'users')]
class User
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 180)]
    private string $organisation;

    #[ORM\Column(length: 64)]
    private string $totalPrice;

    public function getOrganisation(): string
    {
        return $this->organisation;
    }
}
