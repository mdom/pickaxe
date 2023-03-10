package App::pickaxe::ProjectMenu;
use Mojo::Base -signatures, 'App::pickaxe::UI::Index';
use Mojo::URL;

has 'api';
has 'config';
has 'selected_project';

has helpbar  => "q:Quit <Return>:Select";
has projects => sub { shift->api->projects };
has moniker  => 'projects';

sub select_project ( $self, $key ) {
    $self->selected_project( $self->projects->[ $self->current_line ] );
    $self->exit(1);
}

sub update_lines ($self) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->projects_format,
        identifier => {
            p => sub { $_[0] },
            n => sub { state $i = 1; $i++ },
        },
    );
    $self->set_lines( map { $fmt->printf($_) } @{ $self->projects } );
}

sub run ( $self, $bindings ) {
    $self->on( resize => sub { $self->update_lines } );
    $self->update_lines;
    $self->next::method($bindings);
}

sub statusbar ($self) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->projects_status_format,
        identifier => {
            n => sub { scalar $_[0]->projects->@* },
            b => sub { $_[0]->api->safe_base_url->host_port },
        },
    );
    return $fmt->printf($self);
}

1;
