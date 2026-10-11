<?php

class RequestInputs
{
    public function read($req, $key): void
    {
        $a = $req->query->get('limit');
        $b = $this->requestStack->getCurrentRequest()->query->get('page');
        $c = $this->requestStack->getCurrentRequest()->get('sort');
        $d = $req->request->all();
        $e = $req->query->all();
        $f = $req->cookies->get(self::COOKIE_NAME);
        $g = $req->request->get($key);
        $safe = $req->query->getInt('limit');
        $header = $req->headers->get('x-token');
    }
}
