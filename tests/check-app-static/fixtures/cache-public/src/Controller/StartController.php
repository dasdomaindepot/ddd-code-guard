<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Annotation\Route;
use Symfony\Component\HttpKernel\Attribute\Cache;

#[Cache(public: true, maxage: 600)]
class StartController extends AbstractController
{
    #[Route('/')]
    public function index(): Response
    {
        return $this->render('start/index.html.twig');
    }
}
