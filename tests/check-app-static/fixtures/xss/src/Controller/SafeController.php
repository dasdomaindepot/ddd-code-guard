<?php

class SafeController
{
    public function show($request): void
    {
        $a = $request->query->getInt('limit');
        $b = $request->request->getBoolean('enabled');
        $c = $request->query->getEnum('sort', SortOrder::class);
        $d = $request->query->getAlnum('slug');
        $e = $request->query->getDigits('id');
        $f = $request->attributes->get('id');
        $g = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT);
        $h = $request->query->filter('id', null, FILTER_VALIDATE_INT);
        echo htmlspecialchars($a);
    }
}
