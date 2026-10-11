<?php

use Symfony\Component\HttpKernel\Attribute\MapQueryString;
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;

class DemoController
{
    public function show($request)
    {
        $limit = $request->query->get('pagerLimit');
        $name = $request->request->get('name');
        $cookie = $request->cookies->get('token');
        $page = $_GET['page'];
        $post = $_POST['text'];
        $other = $_REQUEST['sort'];
        $stored = $_COOKIE['session'];
        $extra = $_GET['name'];
        $extraTwo = $_POST['title'];
        $generic = $request->get('order');
        $input = filter_input(INPUT_GET, 'offset');
        $safe = $request->query->getInt('limit');
        $safe2 = filter_input(INPUT_GET, 'limit', FILTER_VALIDATE_INT);
        $safe3 = filter_var($request->query->get('id'), FILTER_VALIDATE_INT);
        $cast = (int) $request->query->get('page');
        // guard: roh – wird vor der Ausgabe geprüft
        $known = $request->query->get('known');
        $alsoKnown = $request->query->get('knownToo'); // guard: roh – nur intern
        echo $name;
        print htmlspecialchars($name);
        printf('%s', $name);
        $response = new Response('<b>' . $name . '</b>');
        $markup = new Markup($name, 'UTF-8');
    }

    public function mapped(#[MapQueryString] MissingRules $query, #[MapRequestPayload] ValidatedData $data, #[MapQueryString] ExternalData $unknown, #[MapRequestPayload] OtherRules $other): void {}
}
