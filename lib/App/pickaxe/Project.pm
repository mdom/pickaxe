package App::pickaxe::Project;
use Mojo::URL;

has 'api';
has 'config';

has helpbar   => "q:Quit";
has statusbar => "pickaxe: Projects";
has projects  => sub { shift->api->projects };

sub switch_project ( $self, $key ) {
    $self->api->base_url->path("/projects/$project/");
    $self->update_pages;
}

sub run ( $self, $bindings ) {
    $self->set_lines( @{ $self->projects } );
    $self->next::method($bindings);
}

1;
