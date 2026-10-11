<?php

class ValidatedData
{
    public function __construct(#[Assert\Positive] public int $limit) {}
}
