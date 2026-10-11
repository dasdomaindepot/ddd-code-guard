<?php

class OtherRules
{
    #[Assert\NotBlank]
    private string $internal;
    public int $page;
}
