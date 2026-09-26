<?php

namespace App\Security;

use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\RouterInterface;

class KeycloakAuthenticator
{
    private RouterInterface $router;

    public function __construct(RouterInterface $router)
    {
        $this->router = $router;
    }

    public function authenticate(Request $request): object
    {
        // SSO/OIDC: no local password, redirect to the Keycloak IdP.
        return new RedirectResponse($this->router->generate('app_keycloak'));
    }
}
