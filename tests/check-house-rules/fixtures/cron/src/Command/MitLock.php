<?php

namespace App\Command;

use App\Contract\LockableTrait;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'app:mit-lock', description: 'Mit Sperrung')]
class MitLock extends Command
{
    use LockableTrait;

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $output->writeln('Mit Sperrung');

        return Command::SUCCESS;
    }
}
