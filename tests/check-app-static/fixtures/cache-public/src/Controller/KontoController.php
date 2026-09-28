<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Annotation\Route;
use Symfony\Component\HttpKernel\Attribute\IsGranted;

#[IsGranted('ROLE_USER')]
class KontoController extends AbstractController
{
    #[Route('/konto/profil')]
    public function profile(): Response
    {
        $response = $this->render('konto/profile.html.twig');
        $response->setSharedMaxAge(3600);
        return $response;
    }
}
