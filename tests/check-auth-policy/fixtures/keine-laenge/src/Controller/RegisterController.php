<?php

namespace App\Controller;

use Symfony\Component\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Annotation\Route;

class RegisterController extends AbstractController
{
    #[Route('/register', name: 'app_register')]
    public function register(): Response
    {
        $this->hashPassword('default-password');
        return new Response();
    }

    private function hashPassword(string $plain): string
    {
        return $plain;
    }
}
