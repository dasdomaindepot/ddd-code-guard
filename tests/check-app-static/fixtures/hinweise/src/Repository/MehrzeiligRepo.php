<?php
namespace App\Repository;
class MehrzeiligRepo
{
    public function liste($conn, string $sort): array
    {
        return $conn->fetchAllAssociative(
            'SELECT * FROM orders ORDER BY ' . $sort
        );
    }
}
