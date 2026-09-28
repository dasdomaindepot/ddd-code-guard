<?php

namespace App\Entity;

use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
class Order
{
    #[ORM\Column(type: 'decimal', precision: 10, scale: 2)]
    private string $netto;

    private float $totalPrice;

    private float $taxRate;
}
