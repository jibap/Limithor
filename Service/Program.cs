using App.WindowsService;
using System.ServiceProcess;

class Program
{
    static void Main(string[] args)
    {
        // Crée l'instance du service
        var service = new LimithorService();

        if (Environment.UserInteractive)
        {
            Console.WriteLine("Service démarré en mode console.");
            service.StartForConsole(args);

            Console.WriteLine("Appuyez sur [Enter] pour arrêter le service.");
            Console.ReadLine();

            service.StopForConsole();
        }
        else
        {
            ServiceBase.Run(service);
        }
    }
}
