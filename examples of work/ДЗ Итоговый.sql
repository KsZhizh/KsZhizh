Задания:
--1. Получите количество проектов, подписанных в 2023 году.
--В результат вывести одно значение количества.

select count(project_id)
from project p 
where date_part('year',sign_date)=2023;


--2. Получите общий возраст сотрудников, нанятых в 2022 году.
--Результат вывести одним значением в виде "... years ... month ... days"
--Использование более 2х функций для работы с типом данных дата и время будет являться ошибкой.


select JUSTIFY_INTERVAL(sum(age(current_date,p.birthdate)))
from person p
join employee e on p.person_id=e.person_id 
WHERE e.hire_date BETWEEN '2022-01-01' AND '2022-12-31';


--3. Получите сотрудников, у которого фамилия начинается на М, всего в фамилии 8 букв и который работает дольше других.
--Если таких сотрудников несколько, выведите одного случайного.
--В результат выведите два столбца, в первом должны быть имя и фамилия через пробел, во втором дата найма.


    
	SELECT concat(p.first_name, ' ', p.last_name) AS full_name, e.hire_date
    FROM person p
    JOIN employee e ON p.person_id = e.person_id
    where e.dismissal_date is null
		and p.last_name LIKE 'М%'
      AND length(p.last_name) = 8
   ORDER BY e.hire_date ASC        
   LIMIT 1; 
 

--4. Получите среднее значение полных лет сотрудников, которые уволены и не задействованы на проектах.
--В результат вывести одно среднее значение. Если получаете null, то в результат нужно вывести 0.


SELECT COALESCE(AVG(EXTRACT(YEAR FROM AGE(current_date, p.birthdate))), 0) AS average_dismissed_age
FROM employee e
join person p on e.person_id = p.person_id
left join project pr on e.employee_id = any(pr.employees_id)
	or e.employee_id = pr.project_manager_id
where e.dismissal_date is not null
  and pr.project_id is null;

--5. Чему равна сумма полученных платежей от контрагентов из Жуковский, Россия.
--В результат вывести одно значение суммы.


SELECT SUM(pp.amount) AS total_payment
FROM customer c
join address a on c.address_id = a.address_id
join city c1 on a.city_id = c1.city_id
join country c2 on c1.country_id = c2.country_id
join project p on c.customer_id = p.customer_id
join project_payment pp on p.project_id = pp.project_id
where c2.country_name = 'Россия'
  and c1.city_name = 'Жуковский'
  and pp.fact_transaction_timestamp is not null;

--6. Пусть руководитель проекта получает премию в 1% от стоимости завершенных проектов.
--Если взять завершенные проекты, какой руководитель проекта получит самый большой бонус?
--В результат нужно вывести идентификатор руководителя проекта, его ФИО и размер бонуса.
--Если таких руководителей несколько, предусмотреть вывод всех.


SELECT pm.project_manager_id, per.full_fio, total_prize --вывод full_fio
FROM (
    SELECT 
        project_manager_id,
        SUM(project_cost * 0.01) AS total_prize,
        DENSE_RANK() OVER (ORDER BY SUM(project_cost * 0.01) DESC) AS rnk
    FROM project
    WHERE status = 'Завершен'
    GROUP BY project_manager_id) pm
JOIN employee e ON pm.project_manager_id = e.employee_id
JOIN person per ON e.person_id = per.person_id
WHERE pm.rnk = 1;


--7. Получите накопительный итог планируемых авансовых платежей на каждый месяц в отдельности.
--Выведите в результат те даты планируемых платежей, которые идут после преодаления накопительной суммой значения в 30 000 000
/*Пример:
дата		накопление
2022-06-14	28362946.20
2022-06-20	29633316.30
2022-06-23	34237017.30
2022-06-24	46248120.30
В результат должна попасть дата 2022-06-23*/


with cte_running_total as 
			(select pp.project_payment_id, pp.plan_payment_date, amount, 
				(SUM(amount) over (PARTITION by DATE_TRUNC('month', pp.plan_payment_date) 
						ORDER BY plan_payment_date, project_payment_id)) running_total 
			from project_payment pp   
			where "payment_type" = 'Авансовый'),
	cte2 as
			(SELECT project_payment_id, plan_payment_date, amount, running_total, 
				(row_number () OVER (PARTITION by DATE_TRUNC('month', plan_payment_date) ORDER BY plan_payment_date)) AS running_total_rank
			FROM  cte_running_total
			WHERE running_total >= 30000000)
select project_payment_id, plan_payment_date, running_total
from cte2
where running_total_rank=1;


/*8. Используя рекурсию посчитайте сумму фактических окладов сотрудников из структурного подразделения с id равным 17 и всех дочерних подразделений.
В результат вывести одно значение суммы.*/
    

WITH RECURSIVE r AS (
   	    SELECT *, 0 as level
	    FROM company_structure cs
	    WHERE parent_id = 17
 UNION
        SELECT cs.*, level + 1 as level
    	FROM r
    	join company_structure cs on r.unit_id=cs.parent_id)
SELECT sum(ep.salary*ep.rate)
FROM r
join "position" p on r.unit_id=p.unit_id
join employee_position ep on p.position_id=ep.position_id;


/*9. Задание выполняется одним запросом.

Сделайте сквозную нумерацию фактических платежей по проектам на каждый год в отдельности в порядке даты платежей.
Получите платежи, сквозной номер которых кратен 5.
Выведите скользящее среднее размеров платежей с шагом 2 строки назад и 2 строки вперед от текущей.
Получите сумму скользящих средних значений.
Получите сумму стоимости проектов на каждый год.
Выведите в результат значение года (годов) и сумму проектов, где сумма проектов меньше, чем сумма скользящих средних значений.*/


with cte1 as
		(with numbered_payments as --сквозная нумерация фактических платежей по проектам на каждый год в отдельности в порядке даты платежей.
						(select *, ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('year', fact_transaction_timestamp) ORDER BY fact_transaction_timestamp) AS rn
	    				FROM project_payment
						where fact_transaction_timestamp IS NOT null)
		select *
		from numbered_payments
		WHERE rn % 5 = 0), --платежи, сквозной номер которых кратен 5
	cte2_sum_avg as  --сумма скользящих средних значений
		(select sum(avg2) as total_avg
		from (select *,AVG(amount) OVER (ORDER BY fact_transaction_timestamp 
						ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) avg2 --скользящее среднее размеров платежей с шагом 2 строки назад и 2 строки вперед от текущей.
						FROM cte1)),
	cte3_sum_amount_year as
		(SELECT date_part('year', sign_date) as year, SUM(project_cost) as sum_project
		FROM project
		GROUP BY date_part('year', sign_date)) 
select cte3.year, cte3.sum_project
from cte3_sum_amount_year cte3
CROSS join cte2_sum_avg cte2
where cte3.sum_project < cte2.total_avg
ORDER BY cte3.year;


/*10. Создайте материализованное представление, которое будет хранить отчет следующей структуры:
идентификатор проекта
название проекта
дата последней фактической оплаты по проекту
размер последней фактической оплаты
ФИО руководителей проектов
Названия контрагентов
В виде строки названия типов работ по каждому контрагенту*/

CREATE MATERIALIZED VIEW project_report as 
			with cte as
				(select project_id, "payment_type", fact_transaction_timestamp, amount,
						ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY fact_transaction_timestamp desc) as rn
				 from project_payment
				 where fact_transaction_timestamp is not null),
			 cte2 as 
			 	(select *
			 	 from cte
			 	 where rn=1),
			 cte3 as 
			 	 (select c.*, STRING_AGG(tw.type_of_work_name, ', ') as all_type_of_work
			 	  from customer c
			 	  left join customer_type_of_work ctw on c.customer_id=ctw.customer_id
			 	  left join type_of_work tw on ctw.type_of_work_id=tw.type_of_work_id
			 	  group by c.customer_id)
		select p.project_id, p.project_name, cte2."payment_type", cte2.fact_transaction_timestamp, 
			cte2.amount, concat(p2.first_name,' ',p2.last_name,' ',p2.middle_name), customer_name, all_type_of_work
		from project p
		left join cte2 on  p.project_id=cte2.project_id
		left join employee e on p.project_manager_id=e.employee_id
		left join person p2 on e.person_id=p2.person_id
		left join cte3 on p.customer_id=cte3.customer_id
		order by p.project_id
WITH DATA;

