<?php

namespace App\Security;

use App\Storage\TokenStorage;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Security\Http\Authenticator\AbstractAuthenticator;
use Symfony\Component\Security\Http\Authenticator\Passport\Passport;
use Symfony\Component\Security\Http\Authenticator\Passport\Credentials\PasswordCredentials;
use Symfony\Component\RateLimiter\RateLimiterFactory;

class LoginAuthenticator extends AbstractAuthenticator
{
    public function __construct(
        private RateLimiterFactory $limiter,
        private TokenStorage $storage,
    ) {
    }

    public function authenticate(Request $request): Passport
    {
        $login = $request->request->get('login', '');
        $limiterUse = $this->limiter->create($login);
        $limiterUse->consume();
        $password = $request->request->get('password', '');
        $passport = new Passport($login, new PasswordCredentials($password));
        $this->storage->store($login, $passport);
        return $passport;
    }

    public function supports(Request $request): ?bool
    {
        return str_starts_with($request->getPathInfo(), '/login');
    }
}
